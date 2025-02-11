#!/bin/bash

# Define SSH options
HOME_SERVER="ssh x@85.226.230.106 -p 2222"
INT_SERVER_1="ssh grp13-serv1@193.10.236.126"
INT_SERVER_2="ssh grp13-serv2@193.10.236.127"
UBUNTU_MINI_SERVER="ssh x@192.168.0.78"

# Display menu
echo "Select a server to connect to:"
echo "1) gLiTcH-SERVER"
echo "2) INT Server 1"
echo "3) INT Server 2"
echo "4) Ubuntu-Mini-Server"
echo "5) Exit"
read -p "Enter your choice: " choice

# Handle user input
case $choice in
    1)
        echo "Connecting to gLiTcH-SERVER..."
        exec $HOME_SERVER
        ;;
    2)
        echo "Connecting to INT Server 1..."
        exec $INT_SERVER_1
        ;;
    3)
        echo "Connecting to INT Server 2..."
        exec $INT_SERVER_2
        ;;
    4)
        echo "Connecting to Ubuntu-Mini-Server..."
        exec $UBUNTU_MINI_SERVER
        ;;
    5)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid choice. Exiting..."
        exit 1
        ;;
esac
