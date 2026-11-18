#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/artifact_repo/project_alpha/v1
    mkdir -p /home/user/artifact_repo/project_beta/v2
    mkdir -p /home/user/artifact_repo/legacy_gamma

    # 1. Standard JSON in UTF-8
    cat << 'EOF' > /home/user/artifact_repo/project_alpha/v1/metadata.json
{
  "artifact_id": "alpha-core",
  "version": "1.0.4",
  "checksum": "sha256:abc123def456"
}
EOF

    # 2. XML in ISO-8859-1
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/artifact_repo/project_beta/v2/metadata.xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<metadata>
  <artifact_id>beta-utils-déjà</artifact_id>
  <version>2.1.0</version>
  <checksum>md5:9876543210</checksum>
</metadata>
EOF

    # 3. CSV in UTF-16
    cat << 'EOF' | iconv -f UTF-8 -t UTF-16 > /home/user/artifact_repo/legacy_gamma/metadata.csv
artifact_id,version,checksum
gamma-legacy,0.9.9,sha1:111222333444
EOF

    # 4. Create symlink loops
    mkdir -p /home/user/artifact_repo/loop_dir
    ln -s /home/user/artifact_repo/loop_dir /home/user/artifact_repo/loop_dir/infinite
    ln -s /home/user/artifact_repo /home/user/artifact_repo/project_alpha/v1/up_loop

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/artifact_repo
    chmod -R 777 /home/user
