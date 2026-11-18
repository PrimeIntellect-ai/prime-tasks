#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_project/logs
    mkdir -p /home/user/legacy_project/src

    cat << 'EOF' > /home/user/legacy_project/generate_logs.py
import random
from datetime import datetime, timedelta

flags = ["FLAG_A", "FLAG_B", "FLAG_C", "FLAG_D", "FLAG_E", "EXPERIMENT_BETA"]
with open("/home/user/legacy_project/logs/build_history.log", "w") as f:
    f.write("BuildID,Timestamp,EnvFlags,ExitCode\n")
    for i in range(1, 10001):
        active_flags = random.sample(flags, random.randint(1, 4))
        # Exit code is 1 if EXPERIMENT_BETA is present, 0 otherwise
        exit_code = 1 if "EXPERIMENT_BETA" in active_flags else 0
        timestamp = (datetime(2023, 1, 1) + timedelta(minutes=i*15)).strftime("%Y-%m-%dT%H:%M:%SZ")
        f.write(f"{i},{timestamp},{' '.join(active_flags)},{exit_code}\n")
EOF
    python3 /home/user/legacy_project/generate_logs.py
    rm /home/user/legacy_project/generate_logs.py

    for i in $(seq 1 100); do
        num=$(printf "%02d" $i)
        cat << EOF > /home/user/legacy_project/src/module_${num}.c
void func_${num}() {
    // Dummy function
}
EOF
    done

    echo "int system_state = 0;" >> /home/user/legacy_project/src/module_14.c
    echo "int system_state = 0;" >> /home/user/legacy_project/src/module_73.c

    chmod -R 777 /home/user
