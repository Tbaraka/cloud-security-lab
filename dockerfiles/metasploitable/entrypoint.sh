#!/bin/bash

set -e

echo "Starting Metasploitable Lab..."

# Start SSH
service ssh start

# Start Apache
service apache2 start

# Start FTP
service vsftpd start

echo "Services started successfully."

# Keep container alive
tail -f /dev/null