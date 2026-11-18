#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pyelftools

    mkdir -p /home/user/binaries/

    cat << 'EOF' > /tmp/app1.c
#include <stdio.h>
int main() {
    printf("Safe app\n");
    return 0;
}
EOF

    cat << 'EOF' > /tmp/app2.c
#include <stdio.h>
int main() {
    char buffer[50];
    gets(buffer); // INSECURE
    return 0;
}
EOF

    cat << 'EOF' > /tmp/app3.sh
#!/bin/bash
echo "Not an ELF"
EOF

    gcc /tmp/app1.c -o /home/user/binaries/app1
    gcc -w /tmp/app2.c -o /home/user/binaries/app2
    cp /tmp/app3.sh /home/user/binaries/app3
    chmod +x /home/user/binaries/*

    rm /tmp/app1.c /tmp/app2.c /tmp/app3.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
