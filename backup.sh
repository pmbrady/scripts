#!/bin/bash

# Paths to back up
SRC_DIRS=(
  "/home/docker/containers"
  "/home/docker/immich"
  "/home/docker/immich-db"
)

# NAS destination
DEST_BASE="/home/docker/nas-backup"

# Create a dated backup folder
DATE=$(date +"%Y-%m-%d")
DEST_DIR="$DEST_BASE/$DATE"
mkdir -p "$DEST_DIR"

# Loop through directories and tar them
for DIR in "${SRC_DIRS[@]}"; do
  NAME=$(basename "$DIR")
  TARFILE="$DEST_DIR/${NAME}.tar.gz"

  echo "Backing up $DIR to $TARFILE"

  tar -czf "$TARFILE" "$DIR"
done

# Optional: delete backups older than 14 days
find "$DEST_BASE" -maxdepth 1 -type d -mtime +14 -exec rm -rf {} \;

echo "Backup complete."
