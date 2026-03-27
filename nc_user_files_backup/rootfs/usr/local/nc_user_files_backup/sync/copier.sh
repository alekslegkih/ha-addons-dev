#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# Copy Nextcloud user data directories
# Iterates through user folders and copies their "files" subdirectory
# Supports test mode (simulation) and configurable rsync options
# Uses null-delimited find to safely handle special characters in filenames
copy_user_files() {

    log_debug "copy_nextcloud_data(): start"
    log_debug "SOURCE_PATH=${SOURCE_PATH}"
    log_debug "DEST_PATH=${DEST_PATH}"
    log_debug "TEST_MODE=${TEST_MODE}"
    log_debug "RSYNC_OPTIONS=${RSYNC_OPTIONS}"

    # Validate that source directory exists before processing
    if [ ! -d "${SOURCE_PATH}" ]; then
        bashio::log.red "Source path not found: ${SOURCE_PATH}"
        return 1
    fi

    # Initialize process state flags
    bashio::log "Searching Nextcloud users..."
    bashio::log.blue "Starting file copy process..."

    if [ "${TEST_MODE}" = "true" ]; then
    bashio::log.magenta "Test mode enable. Simulated backup"
    fi

    local SUCCESS=true
    local FOUND_USERS=false

    # Iterate through all first-level directories in SOURCE_PATH
    # Uses -print0 to safely handle spaces and special characters
    while IFS= read -r -d '' dir; do

        # Extract username from directory name
        user="$(basename "$dir")"

        # Skip directories that do not contain a "files" subdirectory
        if [ ! -d "$dir/files" ]; then
            log_debug "Skipping ${user} (no files directory)"
            continue
        fi

        FOUND_USERS=true

        # Define source and destination paths for current user
        SRC="$dir/files/"
        DST="${DEST_PATH}/${user}/files/"

        # Ensure destination directory exists
        mkdir -p "$DST"

        bashio::log "Processing user: ${user}"

        # In test mode, simulate operation without copying files
        if [ "${TEST_MODE}" = "true" ]; then
            sleep 5
            bashio::log.magenta "Simulated backup for ${user}"
            bashio::log.magenta "We are waiting for sleep for 5 seconds."
            continue
        fi

        # Perform file synchronization using rsync
        if rsync ${RSYNC_OPTIONS} "$SRC" "$DST"; then
            bashio::log.green "User ${user} backup completed"
        else
            bashio::log.red "Failed to back up user ${user}"
            SUCCESS=false
        fi

    done < <(
        find "${SOURCE_PATH}" \
            -mindepth 1 -maxdepth 1 \
            -type d \
            -print0
    )

    # Validate that at least one valid user was found
    if [ "${FOUND_USERS}" = "false" ]; then
        bashio::log.red "No Nextcloud users with files directory found"
        return 1
    fi

    # Final result status
    if [ "${SUCCESS}" = "true" ]; then
        bashio::log.green "All users processed successfully"
        return 0
    else
        bashio::log.red "Backup finished with errors"
        return 1
    fi
}
