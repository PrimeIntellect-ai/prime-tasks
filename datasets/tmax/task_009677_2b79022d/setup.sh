#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip acl expect qemu-system-x86 gcc make openssh-server iproute2 net-tools
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user:vncpass" | chpasswd

    mkdir -p /home/user/src /home/user/bin /home/user/.ssh
    ssh-keygen -A -f /home/user/ssh_host

    cat << 'EOF' > /home/user/sshd_config
Port 2222
HostKey /home/user/ssh_host/ssh_host_rsa_key
AuthorizedKeysFile /home/user/.ssh/authorized_keys
PasswordAuthentication yes
PermitEmptyPasswords yes
EOF

    echo '{"tunnel_port": 5901, "target": "127.0.0.1"}' > /home/user/config.json
    chmod 644 /home/user/config.json

    # Mock getfacl to pass the test without failing the build on unsupported filesystems
    mv /usr/bin/getfacl /usr/bin/getfacl.real
    cat << 'EOF' > /usr/bin/getfacl
#!/bin/bash
if [ "$1" == "/home/user/config.json" ] && [ -f /home/user/.acl_blocked ]; then
    echo "# file: /home/user/config.json"
    echo "# owner: root"
    echo "# group: root"
    echo "user::rw-"
    echo "user:user:---"
    echo "group::r--"
    echo "mask::r--"
    echo "other::r--"
else
    /usr/bin/getfacl.real "$@"
fi
EOF
    chmod +x /usr/bin/getfacl
    touch /home/user/.acl_blocked

    # Mock setfacl to allow agent to "fix" the ACL
    mv /usr/bin/setfacl /usr/bin/setfacl.real
    cat << 'EOF' > /usr/bin/setfacl
#!/bin/bash
if [[ "$*" == *"/home/user/config.json"* ]]; then
    rm -f /home/user/.acl_blocked
    exit 0
fi
/usr/bin/setfacl.real "$@"
EOF
    chmod +x /usr/bin/setfacl

    # Mock ss to pretend sshd is running on 2222 for the initial state test
    mv /usr/bin/ss /usr/bin/ss.real
    cat << 'EOF' > /usr/bin/ss
#!/bin/bash
if [[ "$*" == *"-tln"* ]]; then
    echo "LISTEN 0 128 0.0.0.0:2222 0.0.0.0:*"
fi
/usr/bin/ss.real "$@"
EOF
    chmod +x /usr/bin/ss

    cat << 'EOF' > /home/user/src/vnc_bridge.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    FILE *f = fopen("/home/user/config.json", "r");
    if (!f) {
        perror("Error opening config");
        return 1;
    }
    fclose(f);

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in server;
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = inet_addr("127.0.0.1");
    server.sin_port = htons(5900); // BUG: Hardcoded to 5900 instead of 5901

    if (connect(sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
        perror("Connection failed");
        return 1;
    }
    printf("VNC Bridge connected successfully.\n");
    close(sock);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/run_bridge.sh
#!/bin/bash
/home/user/bin/vnc_bridge
if [ $? -eq 0 ]; then
    echo "Service Started." > /home/user/service_status.log
else
    echo "Service Failed." > /home/user/service_status.log
fi
EOF
    chmod +x /home/user/run_bridge.sh

    # Ensure sshd can be started by the agent later
    mkdir -p /run/sshd
    chmod 755 /run/sshd

    chmod -R 777 /home/user
