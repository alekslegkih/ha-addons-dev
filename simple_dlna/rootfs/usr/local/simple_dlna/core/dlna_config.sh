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

    bashio::log.green "minidlna.conf not found. Creating new configuration."

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
        echo "enable_subtitles=no"
        echo "album_art_names=Cover.jpg/cover.jpg/AlbumArtSmall.jpg/albumartsmall.jpg/AlbumArt.jpg/albumart.jpg/Album.jpg/album.jpg/Folder.jpg/folder.jpg/Thumb.jpg/thumb.jpg"
    } > "${CONFIG_FILE}"

    log_debug "New configuration created at ${CONFIG_FILE}"
}


# ------------------------------------------------------------------
# Validate generated configuration
# ------------------------------------------------------------------

validate_generated_config() {

    local file="$1"
    local start_count
    local end_count
    local start_line
    local end_line

    if [ ! -s "${file}" ]; then

        log_debug "Generated configuration is empty: ${file}"
        return 1

    fi

    start_count=$(grep -c \
        '^# <<< SIMPLE_DLNA-MANAGED-START >>>$' \
        "${file}" || true)

    end_count=$(grep -c \
        '^# <<< SIMPLE_DLNA-MANAGED-END >>>$' \
        "${file}" || true)

    if [ "${start_count}" -ne 1 ] || \
       [ "${end_count}" -ne 1 ]; then

        log_debug \
            "Generated config markers invalid: START=${start_count}, END=${end_count}"

        return 1

    fi

    start_line=$(grep -n \
        '^# <<< SIMPLE_DLNA-MANAGED-START >>>$' \
        "${file}" | cut -d: -f1)

    end_line=$(grep -n \
        '^# <<< SIMPLE_DLNA-MANAGED-END >>>$' \
        "${file}" | cut -d: -f1)

    if [ "${start_line}" -ge "${end_line}" ]; then

        log_debug \
            "Generated config block order invalid: START=${start_line}, END=${end_line}"

        return 1

    fi

    return 0
}

# ------------------------------------------------------------------
# Sync managed block
# ------------------------------------------------------------------

sync_managed_block() {

    log_debug "sync_managed_block(): start"

    local start_count
    local end_count
    local start_line
    local end_line
    local current_block
    local new_block

    start_count=$(grep -c \
        '^# <<< SIMPLE_DLNA-MANAGED-START >>>$' \
        "${CONFIG_FILE}" || true)

    end_count=$(grep -c \
        '^# <<< SIMPLE_DLNA-MANAGED-END >>>$' \
        "${CONFIG_FILE}" || true)

    # ----------------------------------------------------------
    # Managed block validation
    # ----------------------------------------------------------

    if [ "${start_count}" -eq 0 ] && \
       [ "${end_count}" -eq 0 ]; then

        log_warn "Managed block not found. Injecting new managed block."

        {
            generate_managed_block
            echo
            cat "${CONFIG_FILE}"
        } > "${CONFIG_FILE}.new"

        if ! validate_generated_config "${CONFIG_FILE}.new"; then

            bashio::log.red \
                "Generated configuration validation failed. Configuration was not modified."

            rm -f "${CONFIG_FILE}.new"
            return 1

        fi

        log_debug "Creating backup ${CONFIG_FILE}.bak"
        cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"

        if ! mv "${CONFIG_FILE}.new" "${CONFIG_FILE}"; then

            bashio::log.red "Failed to replace configuration file"

            rm -f "${CONFIG_FILE}.new"
            return 1

        fi

        log_debug "Managed block injected"
        return

    elif [ "${start_count}" -eq 1 ] && \
         [ "${end_count}" -eq 1 ]; then

        start_line=$(grep -n \
            '^# <<< SIMPLE_DLNA-MANAGED-START >>>$' \
            "${CONFIG_FILE}" | cut -d: -f1)

        end_line=$(grep -n \
            '^# <<< SIMPLE_DLNA-MANAGED-END >>>$' \
            "${CONFIG_FILE}" | cut -d: -f1)

        if [ "${start_line}" -ge "${end_line}" ]; then

            bashio::log.red \
                "Managed configuration block is malformed. Configuration was not modified."

            log_debug \
                "Invalid managed block order: START=${start_line}, END=${end_line}"

            return 1

        fi

    else

        bashio::log.red \
            "Managed configuration block is malformed. Configuration was not modified."

        log_debug \
            "Invalid managed block markers: START=${start_count}, END=${end_count}"

        return 1

    fi

    # ----------------------------------------------------------
    # Compare managed block
    # ----------------------------------------------------------

    current_block="$(extract_current_managed_block | normalize_block)"
    new_block="$(generate_managed_block | normalize_block)"

    log_debug "Comparing current and expected managed blocks"

    if [ "${current_block}" = "${new_block}" ]; then

        log_debug "Managed block is up to date"
        return

    fi

    bashio::log.yellow \
        "Managed block differs from expected configuration. Restoring system-managed values."

    # ----------------------------------------------------------
    # Remove old managed block
    # ----------------------------------------------------------

    awk '
        /<<< SIMPLE_DLNA-MANAGED-START >>>/ {skip=1; next}
        /<<< SIMPLE_DLNA-MANAGED-END >>>/ {skip=0; next}
        !skip
    ' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp"

    # ----------------------------------------------------------
    # Build new configuration
    # ----------------------------------------------------------

    log_debug "Rebuilding configuration with updated managed block"

    {
        generate_managed_block
        echo
        cat "${CONFIG_FILE}.tmp"
    } > "${CONFIG_FILE}.new"

    if ! validate_generated_config "${CONFIG_FILE}.new"; then

        bashio::log.red \
            "Generated configuration validation failed. Configuration was not modified."

        rm -f "${CONFIG_FILE}.new" "${CONFIG_FILE}.tmp"
        return 1

    fi

    # ----------------------------------------------------------
    # Backup and replace
    # ----------------------------------------------------------

    log_debug "Creating backup ${CONFIG_FILE}.bak"
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"

    if ! mv "${CONFIG_FILE}.new" "${CONFIG_FILE}"; then

        bashio::log.red "Failed to replace configuration file"

        rm -f "${CONFIG_FILE}.new" "${CONFIG_FILE}.tmp"
        return 1

    fi

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
