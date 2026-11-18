#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch
    pip3 install pytest

    # Create the user early to ensure /home/user exists properly
    useradd -m -s /bin/bash user || true

    # Create legacy_models directory
    mkdir -p /home/user/legacy_models

    # Create m1.dfa
    cat << 'EOF' > /home/user/legacy_models/m1.dfa
STATES: qEven, qOdd
START: qEven
ACCEPT: qOdd
TRANSITIONS:
qEven, 0 -> qEven
qEven, 1 -> qOdd
qOdd, 0 -> qOdd
qOdd, 1 -> qEven
EOF

    # Create m2.dfa
    cat << 'EOF' > /home/user/legacy_models/m2.dfa
STATES: q0, q1, q2
START: q0
ACCEPT: q2
TRANSITIONS:
q0, 0 -> q0
q0, 1 -> q1
q1, 0 -> q0
q1, 1 -> q2
q2, 0 -> q0
q2, 1 -> q0
EOF

    # Create fixes.patch
    cat << 'EOF' > /home/user/fixes.patch
--- legacy_models/m2.dfa
+++ legacy_models/m2.dfa
@@ -8,4 +8,4 @@
 q1, 0 -> q0
 q1, 1 -> q2
 q2, 0 -> q0
-q2, 1 -> q0
+q2, 1 -> q2
EOF

    # Set permissions
    chmod -R 777 /home/user
