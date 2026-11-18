#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/packages.json
{
  "libcore": {
    "versions": ["1.0.0", "1.2.4", "1.2.5", "2.0.0"],
    "dependencies": {}
  },
  "py-bindings": {
    "versions": ["0.9.0", "1.0.1"],
    "dependencies": {
      "libcore": ">=1.2.0, <2.0.0"
    }
  },
  "rust-service": {
    "versions": ["3.1.0"],
    "dependencies": {
      "libcore": ">=1.2.4, <2.0.0",
      "py-bindings": ">=1.0.0"
    }
  }
}
EOF

    cat << 'EOF' > /home/user/pipeline/mock_builder.sh
#!/bin/bash
PKG=$1
VER=$2

echo "[STATE: INIT] Starting build for $PKG $VER"
echo "[WARN: INIT] unused config"
echo "[STATE: COMPILING]"
if [ "$PKG" == "libcore" ]; then
    echo "[WARN: COMPILING] implicit conversion"
    echo "[WARN: COMPILING] unused variable"
fi
if [ "$PKG" == "py-bindings" ]; then
    echo "[WARN: COMPILING] deprecated API"
    echo "[WARN: COMPILING] type mismatch"
    echo "[WARN: COMPILING] shadow variable"
fi
echo "[STATE: LINKING]"
echo "[WARN: LINKING] slow link"
echo "[STATE: DONE]"
EOF
    chmod +x /home/user/pipeline/mock_builder.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
