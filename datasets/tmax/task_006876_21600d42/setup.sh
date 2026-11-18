#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nasm binutils
pip3 install pytest grpcio grpcio-tools

mkdir -p /home/user

cat << 'EOF' > /home/user/build_manifest.json
[
  {
    "job_id": "ios-build-12",
    "status": "success",
    "assembly_code": ""
  },
  {
    "job_id": "rust-fallback-44",
    "status": "failed",
    "error": "lifetime mismatch",
    "assembly_code": "global _start\nsection .text\n_start:\n  mov rax, 60\n  mov rdi, 105\n  syscall\n"
  }
]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
