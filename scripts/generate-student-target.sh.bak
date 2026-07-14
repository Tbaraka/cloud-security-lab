#!/bin/bash
set -e

STUDENT_ID=$1
if [ -z "$STUDENT_ID" ]; then
  echo "Usage: ./generate-student-target.sh <student-id>"
  exit 1
fi

export STUDENT_ID

envsubst < kubernetes/namespaces/target-namespace-template.yaml | kubectl apply -f -
envsubst < kubernetes/network-policies/allow-from-student-ns.yaml | kubectl apply -n "student-${STUDENT_ID}-target" -f -
envsubst < kubernetes/target-pod-template.yaml | kubectl apply -f -

echo "Target pod deployed for student-${STUDENT_ID} in student-${STUDENT_ID}-target"