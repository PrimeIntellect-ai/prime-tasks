#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-pil \
        tesseract-ocr \
        protobuf-compiler \
        python3-protobuf \
        gcc

    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/manifests/clean
    mkdir -p /home/user/manifests/evil
    mkdir -p /tmp/proto_gen

    # Generate the image
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
text = """C Library FFI Signature:
int check_pkg_cert(const char* pkg_name, const char* pkg_version);
Returns 1 if valid, 0 if invalid.

Security Rules:
REJECT the manifest if ANY of the following are true:
1. check_pkg_cert returns 0 AND is_signed is false.
2. The peer_deps list contains the exact string 'left-pad-malicious'.
3. The package_name starts with 'typo_'."""

img = Image.new('RGB', (600, 300), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/legacy_docs.png')
EOF
    python3 /tmp/gen_image.py

    # Compile the C library
    cat << 'EOF' > /tmp/cert.c
#include <string.h>
int check_pkg_cert(const char* pkg_name, const char* pkg_version) {
    if (pkg_name && strstr(pkg_name, "legacy") != NULL) {
        return 0;
    }
    return 1;
}
EOF
    gcc -shared -o /home/user/libcert.so -fPIC /tmp/cert.c

    # Create Protobuf schema for generation
    cat << 'EOF' > /tmp/proto_gen/manifest.proto
syntax = "proto3";
message Manifest {
  string package_name = 1;
  string version = 2;
  repeated string peer_deps = 3;
  bool is_signed = 4;
}
EOF
    protoc -I/tmp/proto_gen --python_out=/tmp/proto_gen /tmp/proto_gen/manifest.proto

    # Generate corpora
    cat << 'EOF' > /tmp/gen_corpora.py
import sys
sys.path.append('/tmp/proto_gen')
import manifest_pb2

# Clean
for i in range(20):
    m = manifest_pb2.Manifest(package_name=f"pkg_{i}", version="1.0", is_signed=True)
    with open(f"/home/user/manifests/clean/clean_{i}.bin", "wb") as f:
        f.write(m.SerializeToString())

# Evil 1
for i in range(5):
    m = manifest_pb2.Manifest(package_name="legacy_pkg", version="1.0", is_signed=False)
    with open(f"/home/user/manifests/evil/evil1_{i}.bin", "wb") as f:
        f.write(m.SerializeToString())

# Evil 2
for i in range(10):
    m = manifest_pb2.Manifest(package_name=f"pkg_{i}", version="1.0", is_signed=True, peer_deps=["left-pad-malicious", "express"])
    with open(f"/home/user/manifests/evil/evil2_{i}.bin", "wb") as f:
        f.write(m.SerializeToString())

# Evil 3
for i in range(5):
    m = manifest_pb2.Manifest(package_name="typo_lodash", version="1.0", is_signed=True)
    with open(f"/home/user/manifests/evil/evil3_{i}.bin", "wb") as f:
        f.write(m.SerializeToString())
EOF
    python3 /tmp/gen_corpora.py

    # Clean up tmp files
    rm -rf /tmp/proto_gen /tmp/gen_image.py /tmp/cert.c /tmp/gen_corpora.py

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure permissions
    chmod -R 777 /home/user /app
