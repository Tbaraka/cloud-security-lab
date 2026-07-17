#!/bin/bash
set -uo pipefail

provision_student() {
    STUDENT_ID=$1

    if ! [[ "$STUDENT_ID" =~ ^[0-9]{3}$ ]]; then
        echo "Error: student-id must be a 3-digit number."
        return 1
    fi

    NAMESPACE="student-${STUDENT_ID}"
    export STUDENT_ID

    echo ""
    echo "=========================================="
    echo "Provisioning ${NAMESPACE}"
    echo "=========================================="

    ####################################################
    # Step 1 - Namespace
    ####################################################
    echo "=== Step 1: Create Namespace ==="
    if ! ./scripts/generate-student-namespace.sh "$STUDENT_ID"; then
        echo "ERROR: namespace creation failed for $STUDENT_ID"
        return 1
    fi

    ####################################################
    # Step 2 - RBAC
    ####################################################
    echo ""
    echo "=== Step 2: Configure RBAC ==="
    if ! ./scripts/generate-student-rbac.sh "$STUDENT_ID"; then
        echo "ERROR: RBAC creation failed for $STUDENT_ID"
        return 1
    fi

    ####################################################
    # Step 3 - Network Policies
    ####################################################
    echo ""
    echo "=== Step 3: Apply Network Policies ==="

    kubectl apply -n "$NAMESPACE" \
        -f kubernetes/network-policies/default-deny.yaml

    kubectl apply -n "$NAMESPACE" \
        -f kubernetes/network-policies/allow-student-internal.yaml

    envsubst < kubernetes/network-policies/allow-egress.yaml | \
        kubectl apply -n "$NAMESPACE" -f -

    POLICY_COUNT=$(kubectl get networkpolicy \
        -n "$NAMESPACE" \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [ "$POLICY_COUNT" -lt 3 ]; then
        echo "ERROR: Expected 3 NetworkPolicies in $NAMESPACE, found $POLICY_COUNT"
        return 1
    fi

    ####################################################
    # Step 4 - Target Pod (moved before TLS: TLS now
    # depends on the -target namespace existing)
    ####################################################
    echo ""
    echo "=== Step 4: Deploy Target Pod ==="
    if ! ./scripts/generate-student-target.sh "$STUDENT_ID"; then
        echo "ERROR: target pod deployment failed for $STUDENT_ID"
        return 1
    fi

    envsubst < kubernetes/network-policies/allow-from-student-ns.yaml | \
        kubectl apply -n "${NAMESPACE}-target" -f -

    TARGET_POLICY_COUNT=$(kubectl get networkpolicy \
        -n "${NAMESPACE}-target" \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [ "$TARGET_POLICY_COUNT" -lt 1 ]; then
        echo "ERROR: Expected NetworkPolicy in ${NAMESPACE}-target, found $TARGET_POLICY_COUNT"
        return 1
    fi

    TARGET_STATUS=$(kubectl get pod target-metasploitable \
        -n "${NAMESPACE}-target" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")

    ####################################################
    # Step 5 - TLS (wildcard cert, applied in -target ns
    # since that's where the Ingress will live)
    ####################################################
    echo ""
    echo "=== Step 5: Generate TLS ==="
    if ! ./scripts/generate-student-tls.sh "$STUDENT_ID"; then
        echo "ERROR: TLS generation failed for $STUDENT_ID"
        return 1
    fi

    ####################################################
    # Step 6 - Persistent storage (encrypted, via
    # patched local-path-provisioner). Moved before Kali:
    # the Kali pod spec mounts this PVC as a volume, so it
    # must exist first or the pod fails scheduling
    # ("persistentvolumeclaim ... not found") until the
    # scheduler happens to retry after the PVC shows up.
    ####################################################
    echo ""
    echo "=== Step 6: Provision Persistent Storage ==="
    cat <<PVCEOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: student-${STUDENT_ID}-work
  namespace: student-${STUDENT_ID}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 500Mi
PVCEOF

    PVC_STATUS=$(kubectl get pvc "student-${STUDENT_ID}-work" \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")

    ####################################################
    # Step 7 - Kali Pod
    ####################################################
    echo ""
    echo "=== Step 7: Deploy Kali Pod ==="
    if ! ./scripts/generate-student-kali.sh "$STUDENT_ID"; then
        echo "ERROR: kali pod deployment failed for $STUDENT_ID"
        return 1
    fi

    KALI_STATUS=$(kubectl get pod kali-attacker \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")

    ####################################################
    # Step 8 - Ingress (TLS + WAF)
    ####################################################
    echo ""
    echo "=== Step 8: Apply Ingress ==="
    cat <<INGEOF | kubectl apply -n "student-${STUDENT_ID}-target" -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: student-${STUDENT_ID}-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/enable-modsecurity: "true"
    nginx.ingress.kubernetes.io/enable-owasp-core-rules: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - student-${STUDENT_ID}.lab.local
      secretName: student-${STUDENT_ID}-tls
  rules:
    - host: student-${STUDENT_ID}.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: metasploitable
                port:
                  number: 80
INGEOF

    INGRESS_EXISTS=$(kubectl get ingress "student-${STUDENT_ID}-ingress" \
        -n "${NAMESPACE}-target" --ignore-not-found)
    if [ -n "$INGRESS_EXISTS" ]; then
        INGRESS_STATUS="Present"
    else
        INGRESS_STATUS="Missing"
    fi

    ####################################################
    # Verification
    ####################################################
    ACTUAL_PSA=$(kubectl get namespace "$NAMESPACE" \
        -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')

    SA_EXISTS=$(kubectl get serviceaccount "student-${STUDENT_ID}" \
        -n "$NAMESPACE" \
        --ignore-not-found)

    ROLE_EXISTS=$(kubectl get role student-role \
        -n "$NAMESPACE" \
        --ignore-not-found)

    ROLEBINDING_EXISTS=$(kubectl get rolebinding "student-${STUDENT_ID}-binding" \
        -n "$NAMESPACE" \
        --ignore-not-found)

    if [[ -n "$SA_EXISTS" && -n "$ROLE_EXISTS" && -n "$ROLEBINDING_EXISTS" ]]; then
        RBAC_STATUS="Objects present"
    else
        RBAC_STATUS="ERROR: missing objects"
    fi

    CAN_ACCESS_OWN=$(kubectl auth can-i get pods \
        --as="system:serviceaccount:${NAMESPACE}:student-${STUDENT_ID}" \
        -n "$NAMESPACE" 2>/dev/null)

    if [ "$CAN_ACCESS_OWN" = "yes" ]; then
        RBAC_STATUS="${RBAC_STATUS} / access verified"
    else
        RBAC_STATUS="${RBAC_STATUS} / ERROR: cannot access own namespace"
    fi

    if kubectl get secret "student-${STUDENT_ID}-tls" \
        -n "${NAMESPACE}-target" &>/dev/null; then
        TLS_STATUS="Present"
    else
        TLS_STATUS="Missing"
    fi

    ####################################################
    # Summary
    ####################################################
    echo ""
    echo "=========================================="
    echo " Student Environment Summary"
    echo "=========================================="
    echo "Student ID      : $STUDENT_ID"
    echo "Namespace       : $NAMESPACE"
    echo "ServiceAccount  : student-${STUDENT_ID}"
    echo "RBAC            : $RBAC_STATUS"
    echo "Pod Security    : $ACTUAL_PSA"
    echo "NetworkPolicies : $POLICY_COUNT"
    echo "TLS Secret      : $TLS_STATUS"
    echo "Target Pod      : $TARGET_STATUS"
    echo "Target Policy   : $TARGET_POLICY_COUNT"
    echo "PVC (work dir)  : $PVC_STATUS"
    echo "Kali Pod        : $KALI_STATUS"
    echo "Ingress         : $INGRESS_STATUS"
    echo "=========================================="

    if [[ "$RBAC_STATUS" == *ERROR* || "$TLS_STATUS" == "Missing" || \
          "$TARGET_STATUS" != "Running" || "$TARGET_POLICY_COUNT" -lt 1 || \
          "$KALI_STATUS" != "Running" || "$PVC_STATUS" == "Missing" || \
          "$INGRESS_STATUS" == "Missing" ]]; then
        echo "WARNING: Provisioning completed with errors -- see above."
        return 1
    fi

    echo "Provisioning completed successfully."
    return 0
}

####################################################
# Main
####################################################

if [ $# -ne 1 ]; then
    echo "Usage:"
    echo "  $0 <student-id>"
    echo "  $0 all"
    exit 1
fi

if [ "$1" = "all" ]; then
    echo "=========================================="
    echo "Provisioning all 200 student environments"
    echo "=========================================="

    FAILED=()

    for i in $(seq -f "%03g" 1 200); do
        if ! provision_student "$i"; then
            echo "Student $i FAILED"
            FAILED+=("$i")
        fi
    done

    echo ""
    echo "=========================================="
    if [ ${#FAILED[@]} -eq 0 ]; then
        echo "Successfully provisioned all 200 students."
    else
        echo "Provisioned with ${#FAILED[@]} failure(s): ${FAILED[*]}"
        echo "Re-run individually with: $0 <student-id>"
    fi
    echo "=========================================="

    if [ ${#FAILED[@]} -gt 0 ]; then
        exit 1
    fi
else
    provision_student "$1"
fi

####################################################
# Ensure the ingress port-forward is running so
# students/instructor can reach https://student-*.lab.local
# without a manual step every session.
####################################################
echo ""
echo "=== Ensuring ingress port-forward is running ==="
./scripts/lab-portforward.sh start