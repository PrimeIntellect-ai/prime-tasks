#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server sshpass curl gcc
    pip3 install pytest

    # Setup mock VM services
    mkdir -p /var/run/sshd
    useradd -m -s /bin/bash vmsvc
    echo "vmsvc:password123" | chpasswd
    cat << 'EOF' > /etc/ssh/sshd_config_2222
Port 2222
ListenAddress 127.0.0.1
PermitRootLogin no
PasswordAuthentication yes
AllowTcpForwarding yes
X11Forwarding no
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    mkdir -p /app/backend
    echo "OK" > /app/backend/ping

    mkdir -p /app/system
    cat << 'EOF' > /app/system/start_services.sh
#!/bin/bash
/usr/sbin/sshd -f /etc/ssh/sshd_config_2222
cd /app/backend && python3 -m http.server 80 &
EOF
    chmod +x /app/system/start_services.sh

    # Wrapper for pytest to start services
    mv /usr/local/bin/pytest /usr/local/bin/pytest-real
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
/app/system/start_services.sh >/dev/null 2>&1 &
sleep 2
exec /usr/local/bin/pytest-real "$@"
EOF
    chmod +x /usr/local/bin/pytest

    # Setup corpus
    mkdir -p /app/corpus/evil /app/corpus/clean
    for i in {1..5}; do echo "clean file $i" > /app/corpus/clean/file$i.txt; done
    for i in {1..5}; do echo "EVIL_PAYLOAD $i" > /app/corpus/evil/file$i.txt; done
    echo "backtick \` here" > /app/corpus/evil/backtick.txt

    useradd -m -s /bin/bash user || true

    # Setup user files
    cat << 'EOF' > /home/user/sanitizer.c
#include <stdio.h>
int main(int argc, char **argv) {
// TODO
return 0;
}
EOF

    cat << 'EOF' > /home/user/run_sanitizer.sh
#!/bin/bash
./sanitizer "$1"
EOF
    chmod +x /home/user/run_sanitizer.sh

    chmod -R 777 /home/user
