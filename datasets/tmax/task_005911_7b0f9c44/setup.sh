#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip bzip2 tar
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/curated

    cat << 'EOF' > /home/user/rules.ini
[Rules]
alpha = keep
beta = extract_logs
gamma = drop
EOF

    create_artifact() {
        local name=$1
        local proj=$2
        local tmpdir=$(mktemp -d)

        # Create logs.tar.bz2
        mkdir -p $tmpdir/logs
        echo "Log data for $name" > $tmpdir/logs/info.log
        tar -cjf $tmpdir/logs.tar.bz2 -C $tmpdir logs

        # Create payload.zip
        echo "Binary data" > $tmpdir/data.bin
        cd $tmpdir && zip -q payload.zip data.bin logs.tar.bz2
        cd - > /dev/null

        # Create meta.txt
        echo "project=$proj" > $tmpdir/meta.txt

        # Create final tar.gz
        tar -czf /home/user/incoming/${name}.tar.gz -C $tmpdir meta.txt payload.zip

        rm -rf $tmpdir
    }

    create_artifact "art_001" "alpha"
    create_artifact "art_002" "beta"
    create_artifact "art_003" "gamma"
    create_artifact "art_004" "beta"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
