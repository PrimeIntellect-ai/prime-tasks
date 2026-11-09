#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs/app_alpha
    mkdir -p /home/user/configs/app_beta
    mkdir -p /home/user/configs/app_gamma
    mkdir -p /home/user/configs/app_delta
    mkdir -p /home/user/configs/app_epsilon

    cat << 'EOF' > /home/user/configs/app_alpha/metadata.json
{"app_id": 101, "status": "stable"}
EOF
    cat << 'EOF' > /home/user/configs/app_alpha/config.xml
<config><version>2</version><setting>A</setting></config>
EOF

    cat << 'EOF' > /home/user/configs/app_beta/metadata.json
{"app_id": 102, "status": "rotating"}
EOF
    cat << 'EOF' > /home/user/configs/app_beta/config.xml
<config><version>3</version><setting>B</setting></config>
EOF

    cat << 'EOF' > /home/user/configs/app_gamma/metadata.json
{"app_id": 103, "status": "rotating"}
EOF
    cat << 'EOF' > /home/user/configs/app_gamma/config.xml
<config><version>1</version><setting>C</setting></config>
EOF

    cat << 'EOF' > /home/user/configs/app_delta/metadata.json
{"app_id": 104, "status": "deprecated"}
EOF
    cat << 'EOF' > /home/user/configs/app_delta/config.xml
<config><version>5</version><setting>D</setting></config>
EOF

    cat << 'EOF' > /home/user/configs/app_epsilon/metadata.json
{"app_id": 105, "status": "rotating"}
EOF
    cat << 'EOF' > /home/user/configs/app_epsilon/config.xml
<config><version>4</version><setting>E</setting></config>
EOF

    chown -R user:user /home/user/configs
    chmod -R 777 /home/user
