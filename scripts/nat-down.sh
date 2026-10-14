#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="$(dirname "$0")/.nat_state.env"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "Error: State file $STATE_FILE not found. Cannot determine NAT Gateway and EIP to tear down."
    exit 1
fi

# Load saved state
# shellcheck source=/dev/null
source "$STATE_FILE"

echo "=== [1/4] Deleting route 0.0.0.0/0 from $ROUTE_TABLE_ID ==="
aws ec2 delete-route \
    --region "$AWS_REGION" \
    --route-table-id "$ROUTE_TABLE_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    || echo "Route was already removed or not found."

echo "=== [2/4] Deleting NAT Gateway $NAT_ID ==="
aws ec2 delete-nat-gateway \
    --region "$AWS_REGION" \
    --nat-gateway-id "$NAT_ID" \
    --output text > /dev/null

echo "=== [3/4] Waiting for NAT Gateway $NAT_ID to be deleted ==="
aws ec2 wait nat-gateway-deleted --region "$AWS_REGION" --nat-gateway-ids "$NAT_ID"
echo "NAT Gateway $NAT_ID is deleted."

echo "=== [4/4] Releasing Elastic IP $EIP_ALLOC_ID ($EIP_PUBLIC_IP) ==="
# Retry loop to account for AWS ENI release propagation delay
MAX_ATTEMPTS=6
ATTEMPT=1
while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    if aws ec2 release-address --region "$AWS_REGION" --allocation-id "$EIP_ALLOC_ID" 2>/dev/null; then
        echo "Elastic IP $EIP_ALLOC_ID successfully released."
        break
    else
        echo "Waiting for ENI dissociation before releasing EIP (attempt $ATTEMPT/$MAX_ATTEMPTS)..."
        sleep 10
        ((ATTEMPT++))
    fi
done

if [[ $ATTEMPT -gt $MAX_ATTEMPTS ]]; then
    echo "Warning: could not release EIP automatically. Releasing with final attempt:"
    aws ec2 release-address --region "$AWS_REGION" --allocation-id "$EIP_ALLOC_ID"
fi

rm -f "$STATE_FILE"
echo "Ephemeral NAT Gateway teardown complete. Zero recurring charges."
