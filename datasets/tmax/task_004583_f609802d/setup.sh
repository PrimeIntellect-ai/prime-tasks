#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar util-linux
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo_raw/group_alpha/sub1
    mkdir -p /home/user/repo_raw/group_beta

    # Create valid archive 1
    echo "Valid file content 1" > /tmp/file1.txt
    tar -czf /home/user/repo_raw/group_alpha/sub1/app-v1.tar.gz -C /tmp file1.txt

    # Create corrupt archive 1
    echo "This is just a text file, not a tarball" > /home/user/repo_raw/group_alpha/sub1/corrupt-app.tar.gz

    # Create log for group_alpha/sub1
    cat << 'EOF' > /home/user/repo_raw/group_alpha/sub1/publish.log
---
Archive: app-v1.tar.gz
Team: core-infra
Stage: release
Notes: NA
---
Archive: corrupt-app.tar.gz
Team: core-infra
Stage: testing
Notes: Broken build
---
EOF

    # Create valid archive 2
    echo "Valid file content 2" > /tmp/file2.txt
    tar -czf /home/user/repo_raw/group_beta/data-sync.tar.gz -C /tmp file2.txt

    # Create valid archive 3
    echo "Valid file content 3" > /tmp/file3.txt
    tar -czf /home/user/repo_raw/group_beta/data-verify.tar.gz -C /tmp file3.txt

    # Create corrupt archive 2
    dd if=/dev/urandom of=/home/user/repo_raw/group_beta/broken.tar.gz bs=1024 count=5

    # Create log for group_beta
    cat << 'EOF' > /home/user/repo_raw/group_beta/publish.log
---
Archive: data-sync.tar.gz
Team: data-eng
Stage: production
Notes: initial
---
Archive: broken.tar.gz
Team: data-eng
Stage: dev
Notes: oops
---
Archive: data-verify.tar.gz
Team: security
Stage: staging
Notes: validation run
---
EOF

    chown -R user:user /home/user/repo_raw
    chmod -R 777 /home/user
