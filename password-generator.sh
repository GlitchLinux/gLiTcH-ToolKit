#!/bin/bash
PASSWORD=$(openssl rand -base64 12)
echo "Generated Password: $PASSWORD"
