#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifact_repo/pkg_a/src
    mkdir -p /home/user/artifact_repo/pkg_b
    mkdir -p /home/user/artifact_repo/pkg_c

    cat << 'EOF' > /home/user/artifact_repo/pkg_a/src/build.py
name = "pkg_a"
artifact_url = "http://old-repo.local/v1/pkg_a.tar.gz"
version = "1.0"
EOF

    cat << 'EOF' > /home/user/artifact_repo/pkg_b/fetch.py
name = "pkg_b"
# Fetch script
artifact_url = "http://old-repo.local/v1/pkg_b.tar.gz"
EOF

    cat << 'EOF' > /home/user/artifact_repo/pkg_c/build.py
name = "pkg_c"
artifact_url = "https://secure-repo.global/v2/pkg_c.tar.gz"
version = "2.0"
EOF

    cat << 'EOF' > /home/user/artifact_repo/pkg_a/info.txt
artifact_url = "http://old-repo.local/v1/docs.zip"
EOF

    cat << 'EOF' > /home/user/artifact_repo/build_all.py
artifact_url = "http://old-repo.local/v1/master.zip"
print("Building all")
EOF

    chmod -R 777 /home/user
