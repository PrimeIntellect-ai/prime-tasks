#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk coreutils findutils
pip3 install pytest

mkdir -p /home/user/grpc-math-service/protos

cat << 'EOF' > /home/user/grpc-math-service/package.sh
#!/bin/bash
TARGET_DIR=${1:-protos}
mkdir -p build
# BUG 1: find order is not deterministic. Needs 'sort'
find "$TARGET_DIR" -type f -name "*.proto" | xargs cat > build/bundle.proto

# BUG 2: base64 includes newline. Needs 'base64 -w 0' or 'tr -d \n'
sha256sum build/bundle.proto | awk '{print $1}' | base64 > manifest_hash.txt
EOF

chmod +x /home/user/grpc-math-service/package.sh

cat << 'EOF' > /home/user/grpc-math-service/protos/z_service.proto
syntax = "proto3";
service MathService {}
EOF

cat << 'EOF' > /home/user/grpc-math-service/protos/m_types.proto
syntax = "proto3";
message Empty {}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
