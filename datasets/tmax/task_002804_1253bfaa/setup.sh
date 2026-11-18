#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/pipeline.txt
REQUIRE OS_LINUX == 1
EXEC echo "Step 1: Linux setup complete" >> /home/user/execution.log
REQUIRE MEM_GB > 8
EXEC echo "Step 2: Memory check passed" >> /home/user/execution.log
REQUIRE ARCH_X86 == 1
EXEC echo "Step 3: Compiling for x86" >> /home/user/execution.log
REQUIRE MEM_GB < 32
EXEC echo "Step 4: Memory limit check passed" >> /home/user/execution.log
EOF

    chmod -R 777 /home/user
