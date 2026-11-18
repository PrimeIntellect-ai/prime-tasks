#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/
    mkdir -p /app/data/corpora/evil/
    mkdir -p /app/data/corpora/clean/
    mkdir -p /home/user/raw_logs/
    mkdir -p /tmp/source_logs/

    # Download and extract sh-1.14.3
    wget -qO- https://github.com/amoffat/sh/archive/refs/tags/1.14.3.tar.gz | tar -xz -C /app/vendored/

    # Apply perturbations to sh.py (simulate the broken state)
    SH_PY="/app/vendored/sh-1.14.3/sh.py"
    if [ -f "$SH_PY" ]; then
        sed -i 's/self._process_lock.acquire()/#self._process_lock.acquire()/g' "$SH_PY"
        # A naive sed replacement for argument splitting if applicable, or append a note
    else
        # Fallback if path is different
        touch /app/vendored/sh-1.14.3/sh.py
    fi

    # Generate corpora
    python3 -c '
import os
for i in range(50):
    with open(f"/app/data/corpora/clean/clean_{i}.csv", "w") as f:
        f.write("2023-10-01T12:00:00Z, 45.2, 1024.5\n")
for i in range(50):
    with open(f"/app/data/corpora/evil/evil_{i}.csv", "w") as f:
        f.write("2023-10-01T12:00:00Z, 45.2, 1024.5\n")
        if i % 3 == 0:
            f.write("2023-10-01T12:01:00Z, NaN, 1024.5\n")
        elif i % 3 == 1:
            f.write("2023-10-01T12:02:00Z, 1e400, 1024.5\n")
        else:
            f.write("2023-10-01T12:03:00Z, 45.2, inf\n")
'

    # Generate source logs with spaces in filenames
    for i in $(seq 1 20); do
        echo "metric1,metric2" > "/tmp/source_logs/worker $i metrics.csv"
    done

    # Create diagnostic script
    cat << 'EOF' > /home/user/collect_diagnostics.py
import sys
import os
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, "/app/vendored/sh-1.14.3")
import sh

def copy_log(filename):
    sh.cp(f"/tmp/source_logs/{filename}", f"/home/user/raw_logs/{filename}")

if __name__ == "__main__":
    files = os.listdir("/tmp/source_logs")
    with ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(copy_log, files)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /tmp/source_logs
