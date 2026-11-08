#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/mnt

    cat << 'EOF' > /home/user/micro_fstab
/home/user/data/alpha_data /home/user/mnt/alpha_link svc_worker_alpha
/home/user/data/beta_data /home/user/mnt/beta_link svc_worker_beta
/home/user/data/gamma_data /home/user/mnt/gamma_link svc_worker_gamma
EOF

    mkdir -p /home/user/data/beta_data
    ln -s /home/user/data/beta_data /home/user/mnt/beta_link

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
