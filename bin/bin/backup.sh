#!/usr/bin/env bash
#
#  _                _
# | |__   __ _  ___| | ___   _ _ __
# | '_ \ / _` |/ __| |/ / | | | '_ \
# | |_) | (_| | (__|   <| |_| | |_) |
# |_.__/ \__,_|\___|_|\_\\__,_| .__/
#                             |_|
#

set -eo pipefail

# macbook backup volume
# DEST=/Volumes/ccdata/mbp

# linux usb drive
DEST=/media/colin/EB41-ED00/bk

# linux lacie raid
# DEST=

# local test volume
# DEST=/tmp/bk

SOURCE=~
NAME=latest-laptop
BACKUP_PATH="${DEST}/${NAME}"

mkdir -p "${DEST}"

rsync -avhL \
    "${SOURCE}/" \
    --exclude-from=".rsyncignore" \
    "${BACKUP_PATH}"
