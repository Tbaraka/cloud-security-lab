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

start_daemon ssh /usr/sbin/sshd -D
start_daemon apache2 /usr/sbin/apache2ctl -D FOREGROUND
start_daemon vsftpd /usr/sbin/vsftpd /etc/vsftpd.conf

echo "Services started (best effort)."

echo "Startup complete."

exec tail -f /dev/null
