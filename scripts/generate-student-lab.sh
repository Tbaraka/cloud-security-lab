#!/bin/bash
set -uo pipefail

provision_student() {
    STUDENT_ID=$1

    if ! [[ "$STUDENT_ID" =~ ^[0-9]{3}$ ]]; then
        echo "Error: student-id must be a 3-digit number."
        return 1
    fi

    NAMESPACE="student-${STUDENT_ID}"

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

    kubectl apply -n "$NAMESPACE" \
        -f kubernetes/network-policies/allow-dns-egress.yaml

    POLICY_COUNT=$(kubectl get networkpolicy \
        -n "$NAMESPACE" \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [ "$POLICY_COUNT" -lt 3 ]; then
        echo "ERROR: Expected 3 NetworkPolicies in $NAMESPACE, found $POLICY_COUNT"
        return 1
    fi

    ####################################################
    # Step 4 - TLS
    ####################################################
    echo ""
    echo "=== Step 4: Generate TLS ==="
    if ! ./scripts/generate-student-tls.sh "$STUDENT_ID"; then
        echo "ERROR: TLS generation failed for $STUDENT_ID"
        return 1
    fi

    ####################################################
    # Step 5 - Target Pod
    ####################################################
    echo ""
    echo "=== Step 5: Deploy Target Pod ==="
    if ! ./scripts/generate-student-target.sh "$STUDENT_ID"; then
        echo "ERROR: target pod deployment failed for $STUDENT_ID"
        return 1
    fi

    TARGET_STATUS=$(kubectl get pod target-metasploitable \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")

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

    # Real permission check, not just "does the object exist"
    CAN_ACCESS_OWN=$(kubectl auth can-i get pods \
        --as="system:serviceaccount:${NAMESPACE}:student-${STUDENT_ID}" \
        -n "$NAMESPACE" 2>/dev/null)

    if [ "$CAN_ACCESS_OWN" = "yes" ]; then
        RBAC_STATUS="${RBAC_STATUS} / access verified"
    else
        RBAC_STATUS="${RBAC_STATUS} / ERROR: cannot access own namespace"
    fi

    if kubectl get secret "${NAMESPACE}-tls" \
        -n "$NAMESPACE" &>/dev/null; then
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
    echo "=========================================="

    # Return failure if any check actually failed, even though
    # earlier steps succeeded -- don't let a false "success" print.
    if [[ "$RBAC_STATUS" == *ERROR* || "$TLS_STATUS" == "Missing" || "$TARGET_STATUS" != "Running" ]]; then
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

    # Exit non-zero if anything failed, so CI/automation notices
    if [ ${#FAILED[@]} -gt 0 ]; then
        exit 1
    fi
else
    provision_student "$1"
fi