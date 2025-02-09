#!/bin/bash

# Combined script to list SSH login attempts (failed, successful, or both) using journalctl

# Check if systemd journaling is available
if ! command -v journalctl &> /dev/null; then
  echo "journalctl is not installed or not available. Cannot retrieve logs."
  exit 1
fi

# Prompt the user for the choice
echo "Select an option to list SSH login attempts:"
echo "[1] LIST FAILED SSH ATTEMPTS"
echo "[2] LIST SUCCESSFUL SSH LOGINS"
echo "[3] LIST BOTH"
read -p "Enter your choice (1/2/3): " choice

# Function to list failed SSH login attempts
list_failed_logins() {
  echo "[INFO] Listing all failed SSH login attempts..."
  sudo journalctl -u ssh --since "1 week ago" | grep "Failed password" | \
    awk '{print $1, $2, $3, $11}' | \
    sort | \
    uniq -c | \
    sort -n
}

# Function to list successful SSH login attempts
list_successful_logins() {
  echo "[INFO] Listing all successful SSH login attempts..."
  sudo journalctl -u ssh --since "1 week ago" | grep "Accepted password" | \
    awk '{print $1, $2, $3, $11}' | \
    sort | \
    uniq -c | \
    sort -n
}

# Logic based on user's choice
case $choice in
  1)
    list_failed_logins
    ;;
  2)
    list_successful_logins
    ;;
  3)
    echo "[INFO] Listing both failed and successful SSH login attempts..."
    echo "== Failed SSH attempts =="
    list_failed_logins
    echo "== Successful SSH logins =="
    list_successful_logins
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac
