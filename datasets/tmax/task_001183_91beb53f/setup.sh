#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace
    go mod init securebuild
    cat << 'EOF' > artifact.go
package artifact

type ArtifactV1 struct {
    ID   string
    Size int
    Hash string // MD5 of Data
    Data []byte
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
