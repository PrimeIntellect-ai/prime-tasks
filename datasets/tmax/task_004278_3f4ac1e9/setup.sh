#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip graphviz time
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Generate architecture diagram
    cat << 'EOF' > /tmp/dag.dot
digraph G {
    A -> B;
    A -> C;
    B -> D;
    C -> D;
    E;
}
EOF
    dot -Tpng /tmp/dag.dot -o /app/architecture.png

    # Create tasks directory
    mkdir -p /home/user/tasks
    mkdir -p /home/user/logs

    # Task A
    cat << 'EOF' > /home/user/tasks/task_A.py
import time, sys
chunk = "A" * 1024 * 100
for _ in range(15):
    print(chunk)
    sys.stdout.flush()
    time.sleep(2 / 15)
EOF

    # Task B
    cat << 'EOF' > /home/user/tasks/task_B.py
import time, sys
chunk = "B" * 1024 * 100
for _ in range(15):
    print(chunk)
    sys.stdout.flush()
    time.sleep(3 / 15)
EOF

    # Task C
    cat << 'EOF' > /home/user/tasks/task_C.py
import time, sys
chunk = "C" * 1024 * 100
for _ in range(15):
    print(chunk)
    sys.stdout.flush()
    time.sleep(4 / 15)
EOF

    # Task D
    cat << 'EOF' > /home/user/tasks/task_D.py
import time, sys
chunk = "D" * 1024 * 100
for _ in range(15):
    print(chunk)
    sys.stdout.flush()
    time.sleep(2 / 15)
EOF

    # Task E
    cat << 'EOF' > /home/user/tasks/task_E.py
import time, sys
chunk = "E" * 1024 * 100
for _ in range(15):
    print(chunk)
    sys.stdout.flush()
    time.sleep(6 / 15)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
