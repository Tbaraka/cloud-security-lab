#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <student-id>"
  exit 1
fi

STUDENT_ID=$1
export STUDENT_ID

envsubst < kubernetes/namespaces/namespace-template.yaml | kubectl apply -f -