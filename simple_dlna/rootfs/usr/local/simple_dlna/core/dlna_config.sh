#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail


# ------------------------------------------------------------------
# Normalize block (remove trailing spaces and empty lines)
# ------------------------------------------------------------------

normalize_block() {
    sed -e 's/[[:space:]]*$//' -e '/^$/d'
}


# ------------------------------------------------------------------
# Generate managed block
# ------------------------------------------------------------------

generate_managed_block() {
    log_debug "Generating managed DLNA config block"

    cat <<EOF
# <<< SIMPLE_DLNA-MANAGED-START >>>
#
# This block is automatically managed by Simple DLNA addon.
# Changes inside this block will be overwritten.
#
friendly_name=${FRIENDLY_NAME}
media_dir=${DLNA_DIR}
db_dir=${DB_DIR}
port=8200
log_level=general=${LOG_LEVEL}
#
# <<< SIMPLE_DLNA-MANAGED-END >>>
EOF
}

# ------------------------------------------------------------------
# Extract current managed block
# ------------------------------------------------------------------

extract_current_managed_block() {
    log_debug "Extracting current managed block from ${CONFIG_FILE}"

    awk '
        /<<< SIMPLE_DLNA-MANAGED-START >>>/ {capture=1}
        capture {print}
        /<<< SIMPLE_DLNA-MANAGED-END >>>/ {capture=0}
    ' "${CONFIG_FILE}"
}

# ------------------------------------------------------------------
# Create config if missing
# ------------------------------------------------------------------

create_config_if_missing() {

    log_debug "create_config_if_missing(): checking ${CONFIG_FILE}"

    if [ -f "${CONFIG_FILE}" ]; then
        log_debug "Config file already exists"
        return
    fi

    log_green "minidlna.conf not found. Creating new configuration."

    log_debug "Creating DB directory: ${DB_DIR}"
    mkdir -p "${DB_DIR}"

    log_debug "Writing new configuration file"

    {
        generate_managed_block
        echo
        echo "# --- USER CONFIGURATION AREA ---"
        echo "inotify=yes"
        echo "notify_interval=900"
        echo "strict_dlna=no"
        echo "album_art_names=Cover.jpg/cover.jpg/AlbumArtSmall.jpg/albumartsmall.jpg/AlbumArt.jpg/albumart.jpg/Album.jpg/album.jpg/Folder.jpg/folder.jpg/Thumb.jpg/thumb.jpg"
    } > "${CONFIG_FILE}"

    log_debug "New configuration created at ${CONFIG_FILE}"
}

# ------------------------------------------------------------------
# Sync managed block
# ------------------------------------------------------------------

sync_managed_block() {

    log_debug "sync_managed_block(): start"

    if ! grep -q "<<< SIMPLE_DLNA-MANAGED-START >>>" "${CONFIG_FILE}"; then
        log_warn "Managed block not found. Injecting new managed block."

        log_debug "Creating backup ${CONFIG_FILE}.bak"
        cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"

        {
            generate_managed_block
            echo
            cat "${CONFIG_FILE}"
        } > "${CONFIG_FILE}.tmp"

        mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"

        log_debug "Managed block injected"
        return
    fi

    local current_block
    current_block="$(extract_current_managed_block | normalize_block)"

    local new_block
    new_block="$(generate_managed_block | normalize_block)"

    log_debug "Comparing current and expected managed blocks"

    if [ "${current_block}" = "${new_block}" ]; then
        log_debug "Managed block is up to date"
        return
    fi

    log_warn "Managed block differs from expected configuration. Restoring system-managed values."

    log_debug "Creating backup ${CONFIG_FILE}.bak"
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"

    awk '
        /<<< SIMPLE_DLNA-MANAGED-START >>>/ {skip=1; next}
        /<<< SIMPLE_DLNA-MANAGED-END >>>/ {skip=0; next}
        !skip
    ' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp"

    log_debug "Rebuilding configuration with updated managed block"

    {
        generate_managed_block
        echo
        cat "${CONFIG_FILE}.tmp"
    } > "${CONFIG_FILE}"

    rm -f "${CONFIG_FILE}.tmp"

    log_debug "Managed block synchronized"
}


# ------------------------------------------------------------------
# Public entry point
# ------------------------------------------------------------------

init_dlna_config() {
    log_debug "init_dlna_config(): start"

    create_config_if_missing
    sync_managed_block

    log_debug "init_dlna_config(): completed"
}
