#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_protos

    cat << 'EOF' > /home/user/raw_protos/auth.proto
syntax = "proto3";
import "common.proto";
import "user.proto";
message AuthRequest {}
EOF

    cat << 'EOF' > /home/user/raw_protos/user.proto
syntax = "proto3";
import "common.proto";
import "db.proto";
message User {}
EOF

    cat << 'EOF' > /home/user/raw_protos/common.proto
syntax = "proto3";
message Common {}
EOF

    cat << 'EOF' > /home/user/raw_protos/db.proto
syntax = "proto3";
message DbConfig {}
EOF

    cat << 'EOF' > /home/user/raw_protos/gateway.proto
syntax = "proto3";
import "auth.proto";
import "user.proto";
message Gateway {}
EOF

    cat << 'EOF' > /home/user/config.org
SET_TARGET /home/user/compiled_protos
PARSE_DIR /home/user/raw_protos
EMIT_PLAN /home/user/build_order.log
EOF

    chmod -R 777 /home/user
