#!/bin/bash

SERVICE_NAME="apache2"
LOG_FILE="/var/log/auto_healing.log"
DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

if systemctl is-active --quiet "$SERVICE_NAME"
then
    echo "$DATE_TIME - $SERVICE_NAME is running." >> "$LOG_FILE"
else
    echo "$DATE_TIME - ALERT: $SERVICE_NAME is down. Restarting..." >> "$LOG_FILE"

    systemctl restart "$SERVICE_NAME"

    sleep 5

    NEW_DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    if systemctl is-active --quiet "$SERVICE_NAME"
    then
        echo "$NEW_DATE_TIME - SUCCESS: $SERVICE_NAME restarted successfully." >> "$LOG_FILE"
    else
        echo "$NEW_DATE_TIME - ERROR: Failed to restart $SERVICE_NAME." >> "$LOG_FILE"
    fi
fi
