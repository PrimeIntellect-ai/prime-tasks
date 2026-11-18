#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/raw_data/nodes.dump
101|Employee|Alice Smith|{"dept":"Engineering"}
102|Manager|Bob Jones|{"dept":"Engineering","level":3}
103|Project|Project Apollo|{"status":"active","budget":50000}
104|Employee|Charlie Brown|{"dept":"Marketing"}
105|Manager|Diana Prince|{"dept":"Marketing","level":2}
106|Project|Project Zeus|{"status":"inactive","budget":10000}
107|Project|Project Hermes|{"status":"active","budget":20000}
108|Employee|Eve Davis|{"dept":"Engineering"}
EOF

    cat << 'EOF' > /home/user/raw_data/edges.dump
101|102|REPORTS_TO
104|105|REPORTS_TO
108|102|REPORTS_TO
102|103|MANAGES
105|106|MANAGES
105|107|MANAGES
101|104|PEER_OF
EOF

    cat << 'EOF' > /home/user/expected_active_project_paths.tsv
Alice Smith	Bob Jones	Project Apollo
Charlie Brown	Diana Prince	Project Hermes
Eve Davis	Bob Jones	Project Apollo
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
