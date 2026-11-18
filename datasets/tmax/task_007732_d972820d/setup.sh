#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils execstack elfutils
    pip3 install pytest

    mkdir -p /home/user/binaries
    cd /home/user/binaries

    cat << 'EOF' > app1.c
const char* ip = "10.10.10.1";
int main() { return 0; }
EOF

    cat << 'EOF' > app2.c
const char* ip = "192.168.50.5";
int main() { return 0; }
EOF

    cat << 'EOF' > app3.c
const char* ip = "172.16.0.25";
int main() { return 0; }
EOF

    cat << 'EOF' > app4.c
const char* ip = "203.0.113.9";
int main() { return 0; }
EOF

    gcc app1.c -o app1 -z noexecstack
    gcc app2.c -o app2 -z execstack
    gcc app3.c -o app3 -z execstack
    gcc app4.c -o app4 -z noexecstack

    rm *.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
