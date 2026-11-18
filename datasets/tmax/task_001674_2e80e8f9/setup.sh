#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/asm_trace.s
.text
.global _start

_start:
    ; REQUIRE MEM >= 2048
    MOV R0, #1
    ; REQUIRE CPU_EXT NEON
    ADD R1, R0, #1
    ; CONFLICT CPU_EXT MIPS
    SVC 0
    ; REQUIRE CPU_EXT ARM64
EOF

    cat << 'EOF' > /home/user/build_targets.json
[
    {"name": "Phone_A", "MEM": 1024, "CPU_EXT": ["NEON", "ARM64"]},
    {"name": "Phone_B", "MEM": 4096, "CPU_EXT": ["NEON", "ARM64", "MIPS"]},
    {"name": "Phone_C", "MEM": 2048, "CPU_EXT": ["NEON", "ARM64"]},
    {"name": "Phone_D", "MEM": 8192, "CPU_EXT": ["NEON", "ARM64", "VFPV4"]},
    {"name": "Phone_E", "MEM": 2048, "CPU_EXT": ["ARM64"]}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
