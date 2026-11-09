#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/workspace/setup_tmp
    cd /home/user/workspace/setup_tmp

    # Create mock target files with specific binary headers using printf for portability
    printf '\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52' > image_asset.png
    printf '\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' > core_module.so
    printf '\xca\xfe\xba\xbe\x00\x00\x00\x34\x00\x1d\x0a\x00\x06\x00\x0f\x09' > legacy_class.dat

    # Create valid zips
    zip archive_alpha.zip image_asset.png
    zip archive_beta.zip core_module.so

    # Create a corrupted zip
    zip archive_gamma.zip legacy_class.dat
    # Corrupt the zip file by overwriting the first few bytes
    dd if=/dev/urandom of=archive_gamma.zip bs=1 count=16 conv=notrunc

    # Create manifest.json
    cat << 'EOF' > manifest.json
{
  "archive_alpha.zip": "image_asset.png",
  "archive_beta.zip": "core_module.so",
  "archive_gamma.zip": "legacy_class.dat"
}
EOF

    # Package into legacy_project.tar
    tar -cf /home/user/workspace/legacy_project.tar manifest.json archive_alpha.zip archive_beta.zip archive_gamma.zip

    # Cleanup setup temp
    cd /home/user/workspace
    rm -rf /home/user/workspace/setup_tmp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
