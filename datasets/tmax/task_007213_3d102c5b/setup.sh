#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gzip coreutils bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_configs/group_a
    mkdir -p /home/user/raw_configs/group_b

    # Helper to create a .cfl file
    create_cfl() {
        local file=$1
        local host=$2
        local date=$3
        local content=$4

        echo "METADATA - HOST:$host DATE:$date" > "$file"
        echo -n "$content" | gzip | base64 >> "$file"
    }

    # Host: alpha, old version (date 1000)
    create_cfl /home/user/raw_configs/group_a/alpha_old.cfl "alpha" "1000" "setting1=A
[DIRTY_WRITE_FLAG] corrupted data
setting2=B"

    # Host: alpha, new version (date 2000)
    create_cfl /home/user/raw_configs/group_a/alpha_new.cfl "alpha" "2000" "setting1=A_updated
[DIRTY_WRITE_FLAG] partial write...
setting2=B_updated
[DIRTY_WRITE_FLAG] error
setting3=C"

    # Host: beta, old version (date 1500)
    create_cfl /home/user/raw_configs/group_b/beta_old.cfl "beta" "1500" "beta_mode=true
[DIRTY_WRITE_FLAG] buffer overflow
nodes=4"

    # Host: beta, new version (date 2500)
    create_cfl /home/user/raw_configs/group_b/beta_new.cfl "beta" "2500" "beta_mode=false
nodes=8
[DIRTY_WRITE_FLAG] segment fault log
cache=redis"

    chown -R user:user /home/user/raw_configs
    chmod -R 777 /home/user
