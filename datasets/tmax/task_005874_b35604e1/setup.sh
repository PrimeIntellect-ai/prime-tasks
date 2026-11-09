#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backup_metadata.json
[
  {
    "node_id": "master-eu-central-01",
    "region": "eu-central",
    "replicates_from": null
  },
  {
    "node_id": "rep-eu-1",
    "region": "eu-central",
    "replicates_from": "master-eu-central-01"
  },
  {
    "node_id": "rep-us-1",
    "region": "us-east",
    "replicates_from": "master-eu-central-01"
  },
  {
    "node_id": "rep-us-2",
    "region": "us-east",
    "replicates_from": "rep-us-1"
  },
  {
    "node_id": "rep-ap-1",
    "region": "ap-south",
    "replicates_from": "rep-eu-1"
  },
  {
    "node_id": "independent-master",
    "region": "us-west",
    "replicates_from": null
  },
  {
    "node_id": "ind-rep-1",
    "region": "eu-west",
    "replicates_from": "independent-master"
  },
  {
    "node_id": "rep-ap-2",
    "region": "ap-south",
    "replicates_from": "rep-ap-1"
  }
]
EOF

    chmod -R 777 /home/user
