#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential libsqlite3-dev pkg-config
    pip3 install pytest

    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME
    ln -s /usr/local/cargo/bin/* /usr/local/bin/

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/nodes.csv
id,name,department
1,Alice,Engineering
2,Bob,Engineering
3,Charlie,Engineering
4,David,Engineering
5,Eve,Sales
6,Frank,Sales
7,Grace,Sales
8,Heidi,Marketing
9,Ivan,Marketing
10,Judy,Marketing
EOF

    cat << 'EOF' > /home/user/data/edges.csv
source,target,relation_type
2,1,reports_to
3,1,reports_to
4,1,reports_to
5,7,reports_to
6,7,reports_to
8,10,reports_to
9,10,reports_to
1,10,collaborates_with
2,5,collaborates_with
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
