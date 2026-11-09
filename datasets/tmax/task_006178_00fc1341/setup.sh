#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_backups
    mkdir -p /home/user/processed_configs
    cd /home/user/config_backups

    # Create symlink loop
    ln -s loopB loopA
    ln -s loopA loopB
    ln -s . self_loop

    # Create valid archives
    mkdir -p /tmp/stage1
    bash -c 'echo -e "# ENV: production\n# SERVICE: database\nparam=1" > /tmp/stage1/config_a.txt'
    bash -c 'echo -e "# ENV: staging\n# SERVICE: web server\nparam=2" > /tmp/stage1/config_b.txt'
    tar -czf valid1.tar.gz -C /tmp/stage1 .
    rm -rf /tmp/stage1

    mkdir -p /tmp/stage2
    bash -c 'echo -e "Random data\n# ENV: qa\n# SERVICE: auth\nparam=3" > /tmp/stage2/config_c.txt'
    bash -c 'echo -e "# ENV: dev\n# missing service tag\nparam=4" > /tmp/stage2/config_d.txt'
    tar -czf valid2.tar.gz -C /tmp/stage2 .
    rm -rf /tmp/stage2

    # Create corrupted archive
    echo "this is not a tar file" > corrupt1.tar.gz
    head -c 50 valid1.tar.gz > corrupt2.tar.gz

    chown -R user:user /home/user/config_backups
    chown -R user:user /home/user/processed_configs

    chmod -R 777 /home/user
