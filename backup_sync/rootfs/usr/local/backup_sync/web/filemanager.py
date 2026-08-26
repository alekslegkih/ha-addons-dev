#!/usr/bin/env python3

import os
import re
import sys
import shutil
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE))

from flask import Flask, request, url_for, render_template, send_file

from core.logger import (
    log_debug,
    log,
    log_green,
    log_yellow,
    log_red,
)

app = Flask(__name__)

TARGET_PATH = os.environ.get("TARGET_PATH")

if not TARGET_PATH:
    log_yellow("TARGET_PATH not set, using /tmp")
    TARGET_PATH = "/tmp"

TARGET_PATH = os.path.abspath(TARGET_PATH)

VALID_SUFFIXES = (".tar", ".tar.gz")
EXCLUDED_SUFFIXES = (".part",)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

def safe_path(path, fallback=True):
    full_path = os.path.abspath(os.path.join(TARGET_PATH, path))

    if os.path.commonpath([full_path, TARGET_PATH]) != TARGET_PATH:
        log_yellow(f"Blocked path traversal attempt: {path}")

        if fallback:
            return TARGET_PATH

        return None

    return full_path


def fs_path(rel_path):
    path = safe_path(rel_path, fallback=False)

    if path is None:
        return None

    return Path(path)


def human_size(size):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024:
            return f"{size:.1f} {unit}"

        size /= 1024

    return f"{size:.1f} PB"


def smart_filename(filename):
    filename = os.path.basename(filename)

    filename = re.sub(
        r"[^0-9A-Za-zА-Яа-яЁё._\- ]",
        "",
        filename
    )

    return filename.strip()


def list_directory(rel_path):
    current_dir = safe_path(rel_path, fallback=False)

    if current_dir is None:
        raise RuntimeError("Invalid path")

    try:
        entries = os.listdir(current_dir)
    except Exception as e:
        raise RuntimeError(str(e))

    folders = sorted(
        [
            entry
            for entry in entries
            if os.path.isdir(os.path.join(current_dir, entry))
        ],
        key=lambda value: value.lower()
    )

    files = []

    for entry in entries:
        full_path = os.path.join(current_dir, entry)

        if not os.path.isfile(full_path):
            continue

        if entry.endswith(EXCLUDED_SUFFIXES):
            continue

        if not entry.endswith(VALID_SUFFIXES):
            continue

        files.append({
            "name": entry,
            "size": human_size(os.path.getsize(full_path))
        })

    files.sort(key=lambda value: value["name"].lower())

    parent = "/".join(rel_path.split("/")[:-1]) if rel_path else None

    return folders, files, parent


# ------------------------------------------------------------------
# Main page
# ------------------------------------------------------------------

@app.route("/")
def index():

    rel_path = request.args.get("path", "").strip("/")

    current_dir = safe_path(rel_path, fallback=False)

    if current_dir is None:
        return "Invalid path", 400

    log_debug(f"Open path: /{rel_path}")

    try:
        folders, files_raw, parent = list_directory(rel_path)
    except Exception as e:
        log_red(f"Failed to list directory {current_dir}: {e}")
        return "Error", 500

    files = [
        (
            file["name"],
            file["size"]
        )
        for file in files_raw
    ]

    total, used, free = shutil.disk_usage(TARGET_PATH)

    return render_template(
        "index.html",
        folders=folders,
        files=files,
        current_path=rel_path,
        parent=parent,
        total_space=human_size(total),
        used_space=human_size(used),
        free_space=human_size(free)
    )


# ------------------------------------------------------------------
# Delete
# ------------------------------------------------------------------

@app.route("/delete/<path:subpath>", methods=["POST"])
def delete(subpath):

    name = os.path.basename(subpath)
    target = fs_path(subpath)

    if target is None:
        return {
            "status": "error",
            "message": "Invalid path"
        }, 400

    if target.is_dir():
        try:
            target.rmdir()

            log_yellow(f"Folder removed: {name}")

        except OSError as e:
            log_red(f"Delete failed for '{name}' ({target}): {e}")

            if e.errno == 39:
                return {
                    "status": "error",
                    "message": "Folder is not empty"
                }, 400

            return {
                "status": "error",
                "message": str(e)
            }, 400

    elif target.is_file():
        try:
            target.unlink()

            log_yellow(f"File removed: {name}")

        except Exception as e:
            log_red(f"Failed to remove file {name}: {e}")

            return {
                "status": "error",
                "message": str(e)
            }, 500

    else:
        return {
            "status": "error",
            "message": "File or folder not found"
        }, 404

    return {"status": "ok"}


# ------------------------------------------------------------------
# Create directory
# ------------------------------------------------------------------

@app.route("/mkdir/", defaults={"subpath": ""}, methods=["POST"])
@app.route("/mkdir/<path:subpath>", methods=["POST"])
def mkdir(subpath):

    dirname = smart_filename(
        request.form.get("dirname", "")
    )

    if not dirname:
        return {
            "status": "error",
            "message": "Invalid folder name"
        }, 400

    target = safe_path(
        os.path.join(subpath, dirname),
        fallback=False
    )

    if target is None:
        return {
            "status": "error",
            "message": "Invalid folder path"
        }, 400

    try:
        os.makedirs(target, exist_ok=True)

        log_green(f"Folder created: {dirname}")

    except Exception as e:
        log_red(f"Failed to create folder {dirname}: {e}")

        return {
            "status": "error",
            "message": str(e)
        }, 500

    return {"status": "ok"}


# ------------------------------------------------------------------
# API list
# ------------------------------------------------------------------

@app.route("/api/list")
def api_list():

    rel_path = request.args.get("path", "").strip("/")

    try:
        folders, files, parent = list_directory(rel_path)

    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }, 500

    return {
        "status": "ok",
        "current_path": rel_path,
        "parent": parent,
        "folders": folders,
        "files": files
    }


# ------------------------------------------------------------------
# Move
# ------------------------------------------------------------------

@app.route("/move", methods=["POST"])
def move():

    source = request.form.get("source")
    destination = request.form.get("destination")

    if not source or destination is None:
        return {
            "status": "error",
            "message": "Invalid request"
        }, 400

    source_path = fs_path(source)
    dest_dir = fs_path(destination)

    if source_path is None or dest_dir is None:
        return {
            "status": "error",
            "message": "Invalid path"
        }, 400

    if not source_path.exists():
        return {
            "status": "error",
            "message": "Source not found"
        }, 404

    if not dest_dir.is_dir():
        return {
            "status": "error",
            "message": "Destination invalid"
        }, 400

    if source_path.resolve() == dest_dir.resolve():
        return {
            "status": "error",
            "message": "Cannot move into itself"
        }, 400

    if source_path.is_dir():
        try:
            dest_dir.resolve().relative_to(source_path.resolve())

            return {
                "status": "error",
                "message": "Cannot move into its subfolder"
            }, 400

        except ValueError:
            pass

    target_path = dest_dir / source_path.name

    if target_path.exists():
        return {
            "status": "error",
            "message": "Already exists"
        }, 400

    try:
        shutil.move(
            str(source_path),
            str(target_path)
        )

        log(f"Moved: {source}")

    except Exception as e:
        log_red(f"Move failed: {e}")

        return {
            "status": "error",
            "message": "Failed to move file or folder"
        }, 500

    return {"status": "ok"}


# ------------------------------------------------------------------
# Folder list
# ------------------------------------------------------------------

@app.route("/api/folders")
def api_folders():

    base = Path(TARGET_PATH)

    folders = [""] + [
        str(path.relative_to(base))
        for path in base.rglob("*")
        if path.is_dir()
    ]

    folders.sort(key=lambda value: value.lower())

    return {
        "status": "ok",
        "folders": folders
    }


# ------------------------------------------------------------------
# Rename
# ------------------------------------------------------------------

@app.route("/rename", methods=["POST"])
def rename():

    source = request.form.get("source")
    new_name = request.form.get("new_name")

    if not source or not new_name:
        return {
            "status": "error",
            "message": "Invalid request"
        }, 400

    source_path = fs_path(source)

    if source_path is None:
        return {
            "status": "error",
            "message": "Invalid path"
        }, 400

    new_name = smart_filename(new_name)

    if not new_name:
        return {
            "status": "error",
            "message": "Invalid name"
        }, 400

    target_path = source_path.parent / new_name

    if not source_path.exists():
        return {
            "status": "error",
            "message": "Source not found"
        }, 404

    if target_path.exists():
        return {
            "status": "error",
            "message": "Already exists"
        }, 400

    try:
        source_path.rename(target_path)

        log(f"Renamed: {source_path.name} -> {new_name}")

    except Exception as e:
        log_red(f"Rename failed: {e}")

        return {
            "status": "error",
            "message": "Failed to rename file or folder"
        }, 500

    return {"status": "ok"}


# ------------------------------------------------------------------
# Download
# ------------------------------------------------------------------

@app.route("/download/<path:subpath>")
def download(subpath):

    target = fs_path(subpath)

    if target is None:
        return {
            "status": "error",
            "message": "Invalid path"
        }, 400

    if not target.is_file():
        return {
            "status": "error",
            "message": "File not found"
        }, 404

    if target.name.endswith(EXCLUDED_SUFFIXES):
        return {
            "status": "error",
            "message": "Invalid file"
        }, 400

    if not target.name.endswith(VALID_SUFFIXES):
        return {
            "status": "error",
            "message": "Invalid file"
        }, 400

    return send_file(
        str(target),
        as_attachment=True,
        download_name=target.name
    )


# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

if __name__ == "__main__":

    log_green("Starting Backup Manager")

    log_debug("Running on port 8899")
    log_debug(f"Target directory: {TARGET_PATH}")

    import logging
    import flask.cli

    logging.getLogger("werkzeug").setLevel(logging.ERROR)

    flask.cli.show_server_banner = (
        lambda *args, **kwargs: None
    )

    app.run(
        host="0.0.0.0",
        port=8899,
        use_reloader=False
    )
