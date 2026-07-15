#!/bin/bash
set -uo pipefail

PIDFILE=/tmp/lab-portforward.pid

start() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Already running, PID $(cat "$PIDFILE")"
        return 0
    fi
    kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8443:443 \
        > /tmp/lab-portforward.log 2>&1 &
    echo $! > "$PIDFILE"
    sleep 2
    if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Started, PID $(cat "$PIDFILE")"
    else
        echo "Failed to start -- log below:"
        cat /tmp/lab-portforward.log
        rm -f "$PIDFILE"
        return 1
    fi
}

stop() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
        echo "Stopped"
    else
        echo "Not running"
    fi
}

status() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Running, PID $(cat "$PIDFILE")"
    else
        echo "Not running"
    fi
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    status) status ;;
    *) echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
