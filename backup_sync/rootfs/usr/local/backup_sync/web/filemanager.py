#!/usr/bin/env python3

import os
import re
import sys
import subprocess
import shutil
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE))

from flask import (
    Flask,
    request,
    redirect,
    url_for,
    render_template,
    send_file,
)

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

# =========================
# Helpers
# =========================

def safe_path(path):
    full_path = os.path.abspath(os.path.join(TARGET_PATH, path))

    if not os.path.commonpath([full_path, TARGET_PATH]) == TARGET_PATH:
        log_yellow(f"Blocked path traversal attempt: {path}")
        return TARGET_PATH

    return full_path


def fs_path(rel):
    return Path(safe_path(rel))


def human_size(size):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} PB"


def smart_filename(filename: str) -> str:
    filename = os.path.basename(filename)

    filename = re.sub(r"[^0-9A-Za-zА-Яа-яЁё._\- ]", "", filename)

    filename = filename.strip()

    return filename


def list_directory(rel_path):

    current_dir = safe_path(rel_path)

    try:
        entries = os.listdir(current_dir)
    except Exception as e:
        raise RuntimeError(str(e))

    folders = sorted(
        [
            e for e in entries
            if os.path.isdir(os.path.join(current_dir, e))
        ],
        key=lambda x: x.lower()
    )

    files = []

    for e in entries:

        full_path = os.path.join(current_dir, e)

        VALID_SUFFIXES = (".tar", ".tar.gz")
        EXCLUDED_SUFFIXES = (".part",)

        if os.path.isfile(full_path):

            if e.endswith(EXCLUDED_SUFFIXES):
                continue

            if not e.endswith(VALID_SUFFIXES):
                continue

            size_bytes = os.path.getsize(full_path)

            files.append({
                "name": e,
                "size": human_size(size_bytes)
            })

    files = sorted(files, key=lambda x: x["name"].lower())

    parent = "/".join(rel_path.split("/")[:-1]) if rel_path else None

    return folders, files, parent


# =========================
# Web routes
# =========================

@app.route("/", methods=["GET"])
def index():

    rel_path = request.args.get("path", "").strip("/")

    log_debug(f"Open path: /{rel_path}")

    try:

        folders, files_raw, parent = list_directory(rel_path)

    except Exception as e:

        log_red(f"Failed to list directory {safe_path(rel_path)}: {e}")

        return "Error", 500

    files = [
        (f["name"], f["size"])
        for f in files_raw
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


@app.route("/delete/<path:subpath>")
def delete(subpath):

    name = os.path.basename(subpath)
    target = fs_path(subpath)

    if target.is_dir():
        try:
            target.rmdir()
            log_yellow(f"Folder removed: {name}")
        except OSError as e:
            log_red(f"Failed to remove folder {name}: {e}")
    elif target.is_file():
        try:
            target.unlink()
            log_yellow(f"File removed: {name}")
        except Exception as e:
            log_red(f"Failed to remove file {name}: {e}")

    return {"status": "ok"}


@app.route("/mkdir/", defaults={"subpath": ""}, methods=["POST"])
@app.route("/mkdir/<path:subpath>", methods=["POST"])
def mkdir(subpath):

    dirname = request.form.get("dirname")

    if not dirname:
        log_debug("mkdir called without dirname")
        return redirect(url_for("index", path=subpath))

    dirname = smart_filename(dirname)
    target = safe_path(os.path.join(subpath, dirname))

    try:
        os.makedirs(target, exist_ok=True)
        log_green(f"Folder created: {dirname}")
    except Exception as e:
        log_red(f"Failed to create folder {dirname}: {e}")

    return {"status": "ok"}


@app.route("/api/list")
def api_list():

    rel_path = request.args.get("path", "").strip("/")

    try:

        folders, files, parent = list_directory(rel_path)

    except Exception as e:

        return {"status": "error", "message": str(e)}, 500

    return {
        "status": "ok",
        "current_path": rel_path,
        "parent": parent,
        "folders": folders,
        "files": files
    }


@app.route("/move", methods=["POST"])
def move():

    source = request.form.get("source")
    destination = request.form.get("destination")

    if not source or destination is None:
        return {"status": "error"}, 400

    source_path = fs_path(source)
    dest_dir = fs_path(destination)

    if not source_path.exists():
        return {"status": "error", "message": "Source not found"}, 400

    if not dest_dir.is_dir():
        return {"status": "error", "message": "Destination invalid"}, 400

    if source_path.resolve() == dest_dir.resolve():
        return {"status": "error", "message": "Cannot move into itself"}, 400

    if source_path.is_dir():
        if dest_dir.resolve().is_relative_to(source_path.resolve()):
            return {"status": "error", "message": "Cannot move into its subfolder"}, 400

    try:
        target_path = dest_dir / source_path.name

        if target_path.exists():
            return {"status": "error", "message": "Already exists"}, 400

        shutil.move(str(source_path), str(target_path))

    except Exception as e:

        return {"status": "error", "message": str(e)}, 500

    return {"status": "ok"}


@app.route("/api/folders")
def api_folders():

    base = Path(TARGET_PATH)

    folders = [""] + [
        str(p.relative_to(base))
        for p in base.rglob("*")
        if p.is_dir()
    ]

    folders.sort(key=lambda x: x.lower())

    return {
        "status": "ok",
        "folders": folders
    }


@app.route("/rename", methods=["POST"])
def rename():

    source = request.form.get("source")
    new_name = request.form.get("new_name")

    if not source or not new_name:
        return {"status": "error"}, 400

    source_path = fs_path(source)
    parent_dir = source_path.parent

    new_name = smart_filename(new_name)

    if not new_name:
        return {"status": "error", "message": "Invalid name"}, 400

    target_path = parent_dir / new_name

    try:
        if target_path.exists():
            return {"status": "error", "message": "Already exists"}, 400

        source_path.rename(target_path)

        return {"status": "ok"}

    except Exception as e:

        return {"status": "error", "message": str(e)}, 500


@app.route("/download/<path:subpath>")
def download(subpath):

    target = fs_path(subpath)

    if not target.is_file():
        return {"status": "error"}, 404

    return send_file(
        str(target),
        as_attachment=True,
        download_name=target.name
    )


# =========================
# Main
# =========================

if __name__ == "__main__":

    log_green("Starting Backup Manager")
    log_debug(f"Running on port 8899")
    log_debug(f"Target directory: {TARGET_PATH}")

    import logging
    logging.getLogger('werkzeug').setLevel(logging.ERROR)

    import flask.cli
    flask.cli.show_server_banner = lambda *args, **kwargs: None

    app.run(host="0.0.0.0", port=8899, use_reloader=False)
