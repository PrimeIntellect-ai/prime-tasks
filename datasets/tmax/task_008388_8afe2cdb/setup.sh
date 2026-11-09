#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests

    cat << 'EOF' > /home/user/manifests/repo_main.csv
curl,7.80.0,2048,repo_main
curl,7.85.0,2100,repo_main
wget,1.20.1,1500,repo_main
jq,1.6.0,800,repo_main
jq,1.7.0,850,repo_main
tar,1.34.0,2500,repo_main
EOF

    cat << 'EOF' > /home/user/manifests/repo_alt.csv
curl,7.84.0,1950,repo_alt
wget,1.21.1,1600,repo_alt
wget,1.19.9,1200,repo_alt
jq,1.5.0,750,repo_alt
tar,1.34.1,2500,repo_alt
EOF

    cat << 'EOF' > /home/user/requirements.txt
curl,7.81.0
wget,1.20.0
jq,1.6.0
tar,1.34.0
EOF

    cat << 'EOF' > /home/user/expected_install_plan.txt
curl,7.84.0,1950,repo_alt
jq,1.6.0,800,repo_main
tar,1.34.1,2500,repo_alt
wget,1.20.1,1500,repo_main
TOTAL_SIZE,6750
EOF

    chmod -R 777 /home/user
