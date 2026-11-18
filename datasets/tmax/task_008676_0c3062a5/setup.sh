#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd bsdextrautils gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_docs

    printf "\x25\x50\x44\x46\x01\x02\x03\x04\x05" > /home/user/legacy_docs/file_alpha.bin
    printf "\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00" > /home/user/legacy_docs/file_beta.bin
    printf "\x7B\x22\x74\x69\x74\x6C\x65\x22\x3A" > /home/user/legacy_docs/file_gamma.bin
    printf "\x54\x45\x58\x5441504920446f63756d656e746174696f6e207632" > /home/user/legacy_docs/file_delta.bin

    cat << 'EOF' > /home/user/doc_rules.csv
MagicHex,Category,Extension,Action
25504446,print_docs,pdf,copy
89504e47,assets,png,copy
7b227469,metadata,json,copy
54455854,drafts,txt,hex2txt
EOF

    chmod -R 777 /home/user
