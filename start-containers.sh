#!/bin/bash
# Wait until config folder exists
while [ ! -d "$CONFIG_PATH" ]; do
  echo "Waiting for $CONFIG_PATH to be ready..."
  sleep 5
done

# Change to the directory where docker-compose.yml lives
cd /home/docker/docker-compose || exit 1

# Start containers
/usr/local/bin/docker-compose up -d

cd /home/docker/immich || exit 1
/usr/local/bin/docker-compose up -d
