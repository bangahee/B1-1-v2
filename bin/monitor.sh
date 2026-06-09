#!/bin/bash

APP_PATH="/home/agent-admin/agent-app/agent-app"
APP_NAME="agent-app"
PORT="15034"
LOG_FILE="/var/log/agent-app/monitor.log"

echo "====== SYSTEM MONITOR RESULT ======"
echo

echo "[HEALTH CHECK]"

PID=$(pgrep -f "$APP_PATH" | head -n 1)

if [ -z "$PID" ]; then
    echo "Checking process '$APP_NAME'... [FAILED]"
    exit 1
else
    echo "Checking process '$APP_NAME'... [OK] (PID: $PID)"
fi

if ss -tuln | grep -q ":$PORT "; then
    echo "Checking port $PORT... [OK]"
else
    echo "Checking port $PORT... [FAILED]"
    exit 1
fi

echo
echo "[FIREWALL CHECK]"

if sudo /usr/sbin/ufw status | grep -q "Status: active"; then
    echo "Checking UFW status... [OK]"
else
    echo "[WARNING] UFW is not active"
fi

echo
echo "[RESOURCE MONITORING]"

CPU=$(ps -p "$PID" -o %cpu= | awk '{print $1}')
MEM=$(free | awk '/Mem:/ {printf "%.1f", ($3/$2)*100}')
DISK=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')

echo "CPU Usage : ${CPU}%"
echo "MEM Usage : ${MEM}%"
echo "DISK Used : ${DISK}%"

if (( $(echo "$CPU > 20" | bc -l) )); then
    echo "[WARNING] CPU threshold exceeded (${CPU}% > 20%)"
fi

if (( $(echo "$MEM > 10" | bc -l) )); then
    echo "[WARNING] MEM threshold exceeded (${MEM}% > 10%)"
fi

if [ "$DISK" -gt 80 ]; then
    echo "[WARNING] DISK threshold exceeded (${DISK}% > 80%)"
fi

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
echo "[$TIMESTAMP] PID:${PID} CPU:${CPU}% MEM:${MEM}% DISK_USED:${DISK}%" >> "$LOG_FILE"

echo
echo "[INFO] Log appended: $LOG_FILE"

