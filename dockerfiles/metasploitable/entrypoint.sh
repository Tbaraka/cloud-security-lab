#!/bin/bash
set -u
echo "Starting Metasploitable Lab..."

start_daemon() {
    local command_name="$1"
    shift
    echo "Starting ${command_name}..."
    if ! "$@"; then
        echo "${command_name} failed to start; continuing"
    fi
}

service ssh start
service apache2 start
service vsftpd start

echo "Services started."
echo "Startup complete."
exec tail -f /dev/null