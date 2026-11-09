#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/packages_raw

    cat << 'EOF' > /home/user/requirements.txt
libalpha >= 1.2.0
libbeta >= 2.0.0
libgamma >= 0.9.5
EOF

    echo "data1" > /home/user/packages_raw/bGliYWxwaGFfdjEuMTAuMC5tZXRh
    echo "data2" > /home/user/packages_raw/bGliYWxwaGFfdjEuMC41Lm1ldGE=
    echo "data3" > /home/user/packages_raw/bGliYmV0YV92Mi4wLjAubWV0YQ==
    echo "data4" > /home/user/packages_raw/bGliYmV0YV92MS45LjkubWV0YQ==
    echo "data5" > /home/user/packages_raw/bGliZ2FtbWFfdjAuMTAuMC5tZXRh
    echo "data6" > /home/user/packages_raw/bGliZGVsdGFfdjEuMC4wLm1ldGE=

    chown -R user:user /home/user/
    chmod -R 777 /home/user
