#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/project
    mkdir -p /app/legacy_analyzer
    mkdir -p /app/tests/evil
    mkdir -p /app/tests/clean

    # Create a dummy binary to act as the stripped binary fixture
    echo '#!/bin/bash' > /app/legacy_analyzer/analyze_deps
    echo 'echo "Legacy analyzer running..."' >> /app/legacy_analyzer/analyze_deps
    chmod +x /app/legacy_analyzer/analyze_deps

    # Create Clean Corpus
    cat << 'EOF' > /app/tests/clean/valid1.txt
main.o utils.o math.o
utils.o stdlib.h
math.o stdlib.h
EOF

    cat << 'EOF' > /app/tests/clean/valid2.txt
app config.json data.bin
config.json
data.bin
EOF

    # Create Evil Corpus
    # 1. Cycle
    cat << 'EOF' > /app/tests/evil/cycle.txt
a b
b c
c a
EOF

    # 2. Path Traversal
    cat << 'EOF' > /app/tests/evil/traversal.txt
main.o ../../../etc/passwd
EOF

    # 3. Invalid UTF-8
    printf "main.o \xff\xfe\x00\n" > /app/tests/evil/bad_encoding.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
