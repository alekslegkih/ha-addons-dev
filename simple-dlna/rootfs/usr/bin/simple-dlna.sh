#!/bin/sh

set -e
set -o pipefail

CONFIG_DIR="/config"
CONFIG_FILE="$CONFIG_DIR/minidlna.conf"
DB_DIR="$CONFIG_DIR/db"
LOG_DIR="$CONFIG_DIR/log"


MEDIA_DIR="/media"
FRIENDLY_NAME="Simple DLNA"
LOG_LEVEL="warn"

if [ -f /data/options.json ]; then
  MEDIA_DIR=$(jq -r '.media_dir // "/media"' /data/options.json)
  FRIENDLY_NAME=$(jq -r '.friendly_name // "Simple DLNA"' /data/options.json)
  LOG_LEVEL=$(jq -r '.log_level // "warn"' /data/options.json)
fi

mkdir -p \
  "${DB_DIR}" \
  "${LOG_DIR}"

cat > "${CONFIG_FILE}" <<EOF
friendly_name=${FRIENDLY_NAME}
media_dir=${MEDIA_DIR}
db_dir=${DB_DIR}
port=8200
inotify=yes
notify_interval=900
strict_dlna=no
album_art_names=Cover.jpg/cover.jpg/AlbumArtSmall.jpg/albumartsmall.jpg/AlbumArt.jpg/albumart.jpg/Album.jpg/album.jpg/Folder.jpg/folder.jpg/Thumb.jpg/thumb.jpg
log_level=general,artwork,database,inotify,scanner,metadata,http,ssdp,tivo=${LOG_LEVEL}
log_dir=${LOG_DIR}
EOF

echo "Starting minidlna"
exec minidlnad -f "$CONFIG_FILE" -d