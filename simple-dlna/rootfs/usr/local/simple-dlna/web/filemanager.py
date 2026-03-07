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
    log_blue,
)

app = Flask(__name__)

DLNA_DIR = os.environ.get("DLNA_DIR")

if not DLNA_DIR:
    log_yellow("DLNA_DIR not set, using /tmp")
    DLNA_DIR = "/tmp"

DLNA_DIR = os.path.abspath(DLNA_DIR)

# =========================
# Helpers
# =========================

def safe_path(path):
    full_path = os.path.abspath(os.path.join(DLNA_DIR, path))

    if not os.path.commonpath([full_path, DLNA_DIR]) == DLNA_DIR:
        log_yellow(f"Blocked path traversal attempt: {path}")
        return DLNA_DIR

    return full_path

# Convert relative path to safe Path object
# Allows using pathlib helpers (.name .parent .exists etc.)
def fs_path(rel):
    return Path(safe_path(rel))

def human_size(size):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} PB"

def trigger_rescan():
    try:
        log_debug("Triggering minidlna rescan (SIGHUP)")
        subprocess.run(["pkill", "-HUP", "minidlnad"], check=False)
    except Exception as e:
        log_yellow(f"Rescan failed: {e}")

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

        if os.path.isfile(full_path):

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

@app.route("/", methods=["GET", "POST"])
def index():

    rel_path = request.args.get("path", "").strip("/")
    current_dir = safe_path(rel_path)

    log_debug(f"Open path: /{rel_path}")

    if request.method == "POST":

        file = request.files.get("file")

        if file:

            filename = smart_filename(file.filename)

            if not filename:

                if request.headers.get("X-Requested-With") == "XMLHttpRequest":
                    return {"status": "error", "message": "Invalid filename"}, 400

                return redirect(url_for("index", path=rel_path))

            target = os.path.join(current_dir, filename)

            try:

                with open(target, "xb") as f:
                    file.save(f)

                log(f"Uploaded: {filename}")

                trigger_rescan()

            except FileExistsError:

                log_yellow(f"Upload skipped (already exists): {filename}")

                if request.headers.get("X-Requested-With") == "XMLHttpRequest":
                    return {"status": "exists"}, 409

                return redirect(url_for("index", path=rel_path))

            except Exception as e:

                log_red(f"Upload failed: {e}")

                if request.headers.get("X-Requested-With") == "XMLHttpRequest":
                    return {"status": "error", "message": str(e)}, 500

                return redirect(url_for("index", path=rel_path))

            if request.headers.get("X-Requested-With") == "XMLHttpRequest":

                return {
                    "status": "ok",
                    "filename": filename
                }

        return redirect(url_for("index", path=rel_path))

    try:

        folders, files_raw, parent = list_directory(rel_path)

    except Exception as e:

        log_red(f"Failed to list directory {current_dir}: {e}")

        return "Error", 500

    files = [
        (f["name"], f["size"])
        for f in files_raw
    ]

    total, used, free = shutil.disk_usage(DLNA_DIR)

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

    trigger_rescan()

    return {"status": "ok"}


@app.route("/mkdir/", defaults={"subpath": ""}, methods=["POST"])
@app.route("/mkdir/<path:subpath>", methods=["POST"])
def mkdir(subpath):

    dirname = request.form.get("dirname")

    if not dirname:
        log_debug("mkdir called without dirname")
        return redirect(url_for("index", path=subpath))

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

    files = []

    for e in entries:
        full_path = os.path.join(current_dir, e)
        if os.path.isfile(full_path):
            size_bytes = os.path.getsize(full_path)
            files.append({
                "name": e,
                "size": human_size(size_bytes)
            })

    files = sorted(files, key=lambda x: x["name"].lower())

    parent = "/".join(rel_path.split("/")[:-1]) if rel_path else None

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
        trigger_rescan()

    except Exception as e:

        return {"status": "error", "message": str(e)}, 500

    return {"status": "ok"}


@app.route("/api/folders")
def api_folders():

    base = Path(DLNA_DIR)

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
        trigger_rescan()

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
    
@app.route("/api/check-file", methods=["POST"])
def check_file():

    data = request.get_json()

    filename = data.get("filename")
    filesize = data.get("filesize")
    rel_path = data.get("path", "").strip("/")

    if not filename or filesize is None:
        return {"status": "error"}, 400

    current_dir = safe_path(rel_path)
    target = os.path.join(current_dir, filename)

    if os.path.exists(target):
        existing_size = os.path.getsize(target)

        if existing_size == filesize:
            return {
                "status": "exists_same"
            }

        return {
            "status": "exists_different"
        }

    return {
        "status": "not_exists"
    }

# =========================
# Main
# =========================

if __name__ == "__main__":

    log_green("Starting DLNA File Manager")
    log_debug(f"Running on port 8899")
    log_debug(f"DLNA directory: {DLNA_DIR}")

    import logging
    logging.getLogger('werkzeug').setLevel(logging.ERROR)

    from werkzeug.serving import run_simple
    from werkzeug.serving import is_running_from_reloader
    from flask.cli import show_server_banner

    # отключаем banner Flask
    import flask.cli
    flask.cli.show_server_banner = lambda *args, **kwargs: None

    app.run(host="0.0.0.0", port=8899, use_reloader=False)