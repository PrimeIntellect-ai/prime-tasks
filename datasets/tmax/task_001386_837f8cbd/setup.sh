#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/solvers

    cat << 'EOF' > /home/user/solvers/solver_alpha
#!/usr/bin/env python3
import sys
import random
if len(sys.argv) != 2:
    sys.exit(1)
random.seed(int(sys.argv[1]) * 123)
print(round(5.0 + random.random(), 4))
EOF

    cat << 'EOF' > /home/user/solvers/solver_beta
#!/usr/bin/env python3
import sys
import random
if len(sys.argv) != 2:
    sys.exit(1)
random.seed(int(sys.argv[1]) * 456)
print(round(4.2 + random.random() * 1.5, 4))
EOF

    chmod +x /home/user/solvers/solver_alpha
    chmod +x /home/user/solvers/solver_beta

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
