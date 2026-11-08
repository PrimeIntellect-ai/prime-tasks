#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    mkdir -p /home/user/dataset/tmp_archive
    cd /home/user/dataset/tmp_archive

    cat << 'EOF' > config.ini
[Headers]
subj = participant_id
rt = response_time
acc = accuracy
EOF

    cat << 'EOF' > exp_a.tsv
subj	rt	acc
S01	450	0.95
S02	510	0.88
EOF

    cat << 'EOF' > exp_b.tsv
subj	rt	acc
S03	480	0.92
EOF

    zip -r ../archive.zip ./*
    cd ..
    rm -rf tmp_archive
    sha256sum archive.zip > checksum.sha256

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
