#!/usr/bin/env bash
while true; do
    echo "[$(date '+%H:%M:%S') INFO] [launcher]: Starting server..."
    "$@"
    EXIT_CODE=$?
    echo "[$(date '+%H:%M:%S') WARN] [launcher]: Server exited (code $EXIT_CODE), restarting in 3 seconds..."
    sleep 3
done
