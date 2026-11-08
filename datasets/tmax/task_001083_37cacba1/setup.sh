#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-compiler
    pip3 install pytest protobuf grpcio-tools

    mkdir -p /home/user/artifacts
    cat << 'EOF' > /home/user/artifacts/legacy_build.log
BEGIN_ARTIFACT core_lib
STATE INIT
DEPENDS glibc
STATE COMPILED
HASH 7a8b9c0d
STATE PACKAGED
END_ARTIFACT

BEGIN_ARTIFACT ui_module
STATE INIT
DEPENDS core_lib
DEPENDS libpng
STATE FAILED
HASH none
END_ARTIFACT

BEGIN_ARTIFACT data_parser
STATE INIT
STATE COMPILED
HASH ffff1111
END_ARTIFACT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
