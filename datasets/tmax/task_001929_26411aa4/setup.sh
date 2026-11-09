#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar gzip gawk sed coreutils findutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset_archive/exp_set_A
    mkdir -p /home/user/dataset_archive/exp_set_B/logs

    cat << 'EOF' > /home/user/dataset_archive/exp_set_A/sim1.c
__attribute__((section(".exp_data"))) const char exp_metadata[] = "[TRIAL:042;OUTCOME:failure;TIME:162345]";
int main() { return 0; }
EOF
    gcc /home/user/dataset_archive/exp_set_A/sim1.c -o /home/user/dataset_archive/exp_set_A/sim1_bin

    cat << 'EOF' > /home/user/dataset_archive/exp_set_B/sim2.c
__attribute__((section(".exp_data"))) const char exp_metadata[] = "[TRIAL:089;OUTCOME:success;TIME:162399]";
int main() { return 0; }
EOF
    gcc /home/user/dataset_archive/exp_set_B/sim2.c -o /home/user/dataset_archive/exp_set_B/sim2_bin

    cat << 'EOF' > /home/user/dataset_archive/exp_set_A/sim3.c
__attribute__((section(".exp_data"))) const char exp_metadata[] = "[TRIAL:012;OUTCOME:partial;TIME:162310]";
int main() { return 0; }
EOF
    gcc /home/user/dataset_archive/exp_set_A/sim3.c -o /home/user/dataset_archive/exp_set_A/sim3_bin

    echo "Just some log data" > /home/user/dataset_archive/exp_set_B/logs/run.log

    cat << 'EOF' > /home/user/dataset_archive/dummy.c
int main() { return 0; }
EOF
    gcc /home/user/dataset_archive/dummy.c -o /home/user/dataset_archive/dummy_bin

    find /home/user/dataset_archive -name "*.c" -type f -delete

    chmod -R 777 /home/user
