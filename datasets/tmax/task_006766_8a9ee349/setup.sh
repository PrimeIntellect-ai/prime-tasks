#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests
    mkdir -p /home/user/deploy_out

    cat << 'EOF' > /home/user/manifests/frontend.json
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "frontend"
  },
  "spec": {
    "replicas": 3,
    "template": {
      "spec": {
        "containers": [
          {
            "name": "web",
            "image": "registry.local/frontend:2.0"
          }
        ]
      }
    }
  }
}
EOF

    cat << 'EOF' > /home/user/manifests/backend.json
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "backend"
  },
  "spec": {
    "replicas": 3,
    "template": {
      "spec": {
        "containers": [
          {
            "name": "api",
            "image": "registry.local/backend:1.5-canary"
          }
        ]
      }
    }
  }
}
EOF

    cat << 'EOF' > /home/user/plan.csv
app_name,stage
frontend,canary
backend,production
EOF

    chown -R user:user /home/user/manifests /home/user/deploy_out /home/user/plan.csv
    chmod -R 777 /home/user
