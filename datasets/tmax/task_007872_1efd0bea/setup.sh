#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network_edges.csv
source_node,target_node,latency_ms,link_status
alpha,beta,10,active
alpha,gamma,50,active
beta,gamma,15,offline
beta,delta,20,active
gamma,omega,10,active
delta,omega,15,active
alpha,epsilon,5,active
epsilon,delta,40,offline
EOF

    cat << 'EOF' > /home/user/node_metadata.json
{
  "alpha": {"region": "us-east"},
  "beta": {"region": "us-west"},
  "gamma": {"region": "eu-central"},
  "delta": {"region": "ap-south"},
  "epsilon": {"region": "us-east"},
  "omega": {"region": "global"}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
