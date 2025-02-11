#!/bin/bash
LOG_FILE="/var/log/system_monitor.log"
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
MEMORY_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
DISK_USAGE=$(df -h | awk '$NF=="/"{printf "%s", $5}')
echo "$(date) - CPU Usage: $CPU_USAGE%, Memory Usage: $MEMORY_USAGE, Disk Usage: $DISK_USAGE" >> $LOG_FILE
echo "System Monitoring:"
echo "CPU Usage: $CPU_USAGE%"
echo "Memory Usage: $MEMORY_USAGE"
echo "Disk Usage: $DISK_USAGE"
