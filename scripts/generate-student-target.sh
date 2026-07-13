#!/bin/bash
set -e

STUDENT_ID=$1

if [ -z "$STUDENT_ID" ]; then
  echo "Usage: ./generate-student-target.sh <student-id>"
  exit 1
fi

export STUDENT_ID

envsubst < kubernetes/target-pod-template.yaml | kubectl apply -f -

echo "Target pod deployed for student-${STUDENT_ID}"