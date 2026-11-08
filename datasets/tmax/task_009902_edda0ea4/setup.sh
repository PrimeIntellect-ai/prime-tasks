#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deploy_manifest.json
{
  "global_allowed_regions": ["us-east-1", "eu-central-1", "ap-northeast-1"],
  "services": [
    {
      "name": "payment-gateway",
      "version": "v2.1.4",
      "memory_limit_mb": 1024,
      "required_memory_mb": 512,
      "target_region": "us-east-1"
    },
    {
      "name": "cache-node",
      "version": "v1.0.0",
      "memory_limit_mb": 256,
      "required_memory_mb": 512,
      "target_region": "eu-central-1"
    },
    {
      "name": "auth-service",
      "version": "v3.0.1",
      "memory_limit_mb": 512,
      "required_memory_mb": 512,
      "target_region": "ap-northeast-1"
    },
    {
      "name": "search-index",
      "version": "v1.9.2",
      "memory_limit_mb": 2048,
      "required_memory_mb": 1024,
      "target_region": "us-west-2"
    },
    {
      "name": "notification-worker",
      "version": "v4.5.0",
      "memory_limit_mb": 512,
      "required_memory_mb": 256,
      "target_region": "eu-central-1"
    }
  ]
}
EOF

    chmod -R 777 /home/user
