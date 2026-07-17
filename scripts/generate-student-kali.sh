#!/bin/bash
set -e

STUDENT_ID=$1
if [ -z "$STUDENT_ID" ]; then
  echo "Usage: ./generate-student-kali.sh <student-id>"
  exit 1
fi

export STUDENT_ID

envsubst < kubernetes/kali-pod-template.yaml | kubectl apply -f -

echo "Kali pod deployed for student-${STUDENT_ID}"
