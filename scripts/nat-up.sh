#!/usr/bin/env bash
set -euo pipefail

# Configuration
AWS_REGION="eu-central-1"
SUBNET_ID="subnet-022224dd824ee5a4f"     # timecapsule-dev-public-a
ROUTE_TABLE_ID="rtb-0ad41b15e5a7a9f09" # timecapsule-dev-private-rt
STATE_FILE="$(dirname "$0")/.nat_state.env"

echo "=== [1/5] Allocating Elastic IP for ephemeral NAT Gateway ==="
ALLOC_JSON=$(aws ec2 allocate-address \
    --region "$AWS_REGION" \
    --domain vpc \
    --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=timecapsule-dev-nat-eip},{Key=Project,Value=timecapsule},{Key=Owner,Value=student},{Key=Lab,Value=lab3}]' \
    --output json)

EIP_ALLOC_ID=$(echo "$ALLOC_JSON" | grep -o '"AllocationId": "[^"]*' | cut -d'"' -f4)
EIP_PUBLIC_IP=$(echo "$ALLOC_JSON" | grep -o '"PublicIp": "[^"]*' | cut -d'"' -f4)
echo "Allocated Elastic IP: $EIP_PUBLIC_IP (AllocationId: $EIP_ALLOC_ID)"

echo "=== [2/5] Creating NAT Gateway in public-a ($SUBNET_ID) ==="
NAT_JSON=$(aws ec2 create-nat-gateway \
    --region "$AWS_REGION" \
    --subnet-id "$SUBNET_ID" \
    --allocation-id "$EIP_ALLOC_ID" \
    --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=timecapsule-dev-nat-a},{Key=Project,Value=timecapsule},{Key=Owner,Value=student},{Key=Lab,Value=lab3}]' \
    --output json)

NAT_ID=$(echo "$NAT_JSON" | grep -o '"NatGatewayId": "[^"]*' | cut -d'"' -f4)
echo "Created NAT Gateway: $NAT_ID"

echo "=== [3/5] Waiting for NAT Gateway to become available ==="
aws ec2 wait nat-gateway-available --region "$AWS_REGION" --nat-gateway-ids "$NAT_ID"
echo "NAT Gateway $NAT_ID is now AVAILABLE."

echo "=== [4/5] Adding default route 0.0.0.0/0 to private-rt ($ROUTE_TABLE_ID) ==="
aws ec2 create-route \
    --region "$AWS_REGION" \
    --route-table-id "$ROUTE_TABLE_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --nat-gateway-id "$NAT_ID" \
    --output text > /dev/null
echo "Route 0.0.0.0/0 -> $NAT_ID successfully created."

echo "=== [5/5] Saving state to $STATE_FILE ==="
cat > "$STATE_FILE" << EOF
NAT_ID=$NAT_ID
EIP_ALLOC_ID=$EIP_ALLOC_ID
EIP_PUBLIC_IP=$EIP_PUBLIC_IP
ROUTE_TABLE_ID=$ROUTE_TABLE_ID
AWS_REGION=$AWS_REGION
EOF
chmod 600 "$STATE_FILE"

echo "Ephemeral NAT Gateway successfully deployed. Internet access enabled for private subnets."
