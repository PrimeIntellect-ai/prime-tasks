#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create graph_data directory and files
    mkdir -p /home/user/graph_data

    cat << 'EOF' > /home/user/graph_data/databases.csv
db1,UserDB,true
db2,LogDB,false
db3,FinancialDB,true
db4,MetricsDB,true
db5,AuthDB,true
EOF

    cat << 'EOF' > /home/user/graph_data/policies.csv
pol1,30,true
pol2,15,true
pol3,90,false
pol4,60,true
EOF

    cat << 'EOF' > /home/user/graph_data/has_policy.csv
db1,pol1
db3,pol3
db4,pol2
db5,pol4
EOF

    # Make sure cargo is in the user's path by installing it globally or adding to profile
    echo 'export PATH="/root/.cargo/bin:$PATH"' >> /home/user/.bashrc

    chmod -R 777 /home/user
    chmod -R 777 /root/.cargo || true
    chmod -R 777 /root/.rustup || true
