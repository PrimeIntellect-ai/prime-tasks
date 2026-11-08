#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs('/home/user', exist_ok=True)

lines = []
# Chunk 1 (15 lines) - valid
lines.extend([
    "junk1",
    "[VALID_BLOCK]",
    "junk2",
    ">>> PATH: src/main.py <<<",
    "def hello_world():",
    "    print('Hello')",
    ">>> END <<<",
    "junk3",
    "junk4",
    ">>> PATH: docs/readme.md <<<",
    "# Documentation",
    "This is the readme.",
    ">>> END <<<",
    "junk5",
    "junk6"
])

# Chunk 2 (15 lines) - invalid (no VALID_BLOCK)
lines.extend([
    "bad_junk",
    ">>> PATH: evil/hidden.py <<<",
    "print('Should not be extracted')",
    ">>> END <<<"
] + ["filler"] * 11)

# Chunk 3 (15 lines) - valid
lines.extend([
    "some log data",
    "[VALID_BLOCK]",
    ">>> PATH: src/utils/helper.py <<<",
    "def add(a, b):",
    "    return a + b",
    ">>> END <<<",
] + ["filler2"] * 9)

with open('/home/user/archive.txt', 'w') as f:
    f.write('\n'.join(lines) + '\n')
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
