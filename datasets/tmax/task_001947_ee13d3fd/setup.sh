#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access_logs.json
[
  {"user": "U_Alice", "accessed_system": "GatewayA"},
  {"user": "U_Bob", "accessed_system": "GatewayA"},
  {"user": "U_Charlie", "accessed_system": "GatewayB"},
  {"user": "U_Dave", "accessed_system": "GatewayB"},
  {"user": "U_Eve", "accessed_system": "GatewayC"}
]
EOF

    cat << 'EOF' > /home/user/system_topology.csv
source_system,target_system
GatewayA,AuthService
GatewayB,AuthService
GatewayC,PublicAPI
AuthService,DatabaseMain
AuthService,LogServer
PublicAPI,LogServer
DatabaseMain,PaymentGateway
DatabaseMain,BackupStore
PaymentGateway,ExternalBankAPI
EOF

    chmod -R 777 /home/user
