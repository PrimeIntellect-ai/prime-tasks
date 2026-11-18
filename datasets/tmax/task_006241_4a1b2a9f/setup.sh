#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs/app_alpha
    mkdir -p /home/user/configs/app_beta
    mkdir -p /home/user/configs/app_gamma
    mkdir -p /home/user/archives

    # Create app_alpha (Success)
    echo "alpha_setting=1" > /home/user/configs/app_alpha/main.conf

    # Create app_beta (Failed)
    echo "beta_setting=2" > /home/user/configs/app_beta/config.ini
    ln -s /home/user/configs/app_beta/config.ini /home/user/configs/app_beta/valid_link.ini
    ln -s /home/user/configs/app_beta/loop2.lnk /home/user/configs/app_beta/loop1.lnk
    ln -s /home/user/configs/app_beta/loop1.lnk /home/user/configs/app_beta/loop2.lnk

    # Create app_gamma (Failed)
    echo "gamma_setting=3" > /home/user/configs/app_gamma/settings.conf
    ln -s /home/user/configs/app_gamma/self_loop.lnk /home/user/configs/app_gamma/self_loop.lnk
    ln -s /home/user/configs/app_beta/config.ini /home/user/configs/app_gamma/cross_link.ini

    # Create multi-line log
    cat << 'EOF' > /home/user/backup.log
[2023-10-01 12:00:00] BACKUP JOB 101
TARGET: /home/user/configs/app_alpha
STATUS: SUCCESS
--
[2023-10-01 12:05:00] BACKUP JOB 102
TARGET: /home/user/configs/app_beta
STATUS: FAILED
REASON: SYMLINK_LOOP
--
[2023-10-01 12:10:00] BACKUP JOB 103
TARGET: /home/user/configs/app_gamma
STATUS: FAILED
REASON: SYMLINK_LOOP
EOF

    chmod -R 777 /home/user
