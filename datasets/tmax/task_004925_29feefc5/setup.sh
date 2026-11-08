#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    gcc -O2 -o /app/legacy_oracle -xc - << 'EOF'
#include <stdio.h>
#include <stdint.h>
int main() {
    int32_t val;
    while (scanf("%d", &val) == 1) {
        int32_t step1 = (val * 1103515245) + 12345;
        int32_t step2 = step1 ^ (val >> 16);
        printf("%d ", step2);
    }
    return 0;
}
EOF
    strip /app/legacy_oracle
    chmod +x /app/legacy_oracle

    mkdir -p /home/user/signal_port/tests

    cat << 'EOF' > /home/user/signal_port/processor.py
def process_signal(data: list[int]) -> list[int]:
    """Applies the legacy filter to a list of integers."""
    result = []
    for val in data:
        # BUG: Missing 32-bit signed integer overflow emulation
        step1 = (val * 1103515245) + 12345
        step2 = step1 ^ (val >> 16)
        result.append(step2)
    return result
EOF

    cat << 'EOF' > /home/user/signal_port/requirements.txt
numpy==1.24.3
pandas==2.1.0
pytest==7.4.0
urllib3<1.26
requests>=2.31.0 # Requires urllib3>=1.26, causing a pip conflict
EOF

    cat << 'EOF' > /home/user/signal_port/tests/test_processor.py
from processor import process_signal
def test_basic():
    assert process_signal([0, 1, 2]) == [12345, 1103527590, -2087937361] # 2nd index overflows in C
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
