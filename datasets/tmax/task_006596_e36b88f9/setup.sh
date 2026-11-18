#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/config_log.txt
1620000000|S1|  Nginx= V1.1  
1620000005|S2|Apache (2.4)
1620000010|S1|Nginx= V1.2!
1620000015|S3|IIS
1620000020|S2|Apache (2.4.1) - Patch
1620000025|S1|Nginx V1.3
1620000030|S99|Custom_Config_@99
EOF

    cat << 'EOF' > /home/user/metadata.txt
S1|admin-web@company.com
S2|bob_ops@company.com
S3|charlie.sys@company.com
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
