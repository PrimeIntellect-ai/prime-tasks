#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssh-server
    pip3 install pytest paramiko

    mkdir -p /app/ssh
    mkdir -p /app/bin
    mkdir -p /truth

    # Create auth_hook.c and compile
    cat << 'EOF' > /tmp/auth_hook.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    if (strcmp(argv[1], "b4ckd00r_adm1n_xyz") == 0) {
        printf("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n");
        return 0;
    }
    return 1;
}
EOF
    gcc -o /app/bin/auth_hook /tmp/auth_hook.c
    strip /app/bin/auth_hook
    rm /tmp/auth_hook.c
    chmod +x /app/bin/auth_hook

    # Create broken sshd_config
    cat << 'EOF' > /app/ssh/sshd_config
# Broken SSHD config
Port 22
ListenAddress 0.0.0.0
# Missing AuthorizedKeysCommand
EOF

    # Create traffic_generator.py
    cat << 'EOF' > /app/traffic_generator.py
import time
import sys

def main():
    while True:
        time.sleep(1)

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/traffic_generator.py

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
echo "Starting services..."
python3 /app/traffic_generator.py &
EOF
    chmod +x /app/start_services.sh

    # Create truth log
    cat << 'EOF' > /truth/held_out_auth.log
Dec 15 10:22:33 host sshd[1234]: Accepted publickey for b4ckd00r_adm1n_xyz from 192.168.1.55 port 44322 ssh2
Dec 15 10:22:35 host sshd[1235]: Invalid user admin from 10.1.2.3 port 33444
Dec 15 10:22:36 host sshd[1236]: Accepted publickey for b4ckd00r_adm1n_xyz from 10.0.0.9 port 44322 ssh2
Dec 15 10:22:37 host sshd[1237]: Accepted publickey for b4ckd00r_adm1n_xyz from 172.16.5.101 port 44322 ssh2
Dec 15 10:22:38 host sshd[1238]: Accepted publickey for b4ckd00r_adm1n_xyz from 198.51.100.22 port 44322 ssh2
EOF

    # Create evaluate.py
    cat << 'EOF' > /truth/evaluate.py
import subprocess
import sys

truth_ips = set(["192.168.1.55", "10.0.0.9", "172.16.5.101", "198.51.100.22"])

try:
    out = subprocess.check_output(["python3", "/home/user/detector.py", "/truth/held_out_auth.log"], text=True)
    agent_ips = set([line.strip() for line in out.split('\n') if line.strip()])
except Exception as e:
    print(f"Error running detector: {e}")
    sys.exit(1)

tp = len(truth_ips.intersection(agent_ips))
fp = len(agent_ips - truth_ips)
fn = len(truth_ips - agent_ips)

precision = tp / (tp + fp) if (tp + fp) > 0 else 0
recall = tp / (tp + fn) if (tp + fn) > 0 else 0
f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

print(f"F1 Score: {f1:.4f}")
if f1 >= 0.95:
    sys.exit(0)
else:
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
