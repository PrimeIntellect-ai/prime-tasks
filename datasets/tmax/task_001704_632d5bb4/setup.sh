#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc file binutils coreutils
    pip3 install pytest

    mkdir -p /home/user/incident/uploads

    printf "\xFF\xD8\xFF\xE0 dummy jpeg" > /home/user/incident/uploads/banner.jpg
    printf "\x89\x50\x4E\x47\x0D\x0A\x1A\x0A dummy png" > /home/user/incident/uploads/logo.png

    cat << 'EOF' > /tmp/malicious.c
#include <stdio.h>
int main() {
    const char* hash = "BDOOR_HASH=06c8b9319e0edb8cc15da9be6e75a7c5b6140d39e80119dbbcde1c01ff0f23d1";
    const char* salt = "BDOOR_SALT=k9Xp";
    return 0;
}
EOF
    gcc /tmp/malicious.c -o /home/user/incident/uploads/profile.gif
    rm /tmp/malicious.c

    cat << 'EOF' > /home/user/incident/firewall.sh
#!/bin/bash
iptables -F
iptables -A INPUT -p tcp -s 192.168.1.100 --dport 80 -j ACCEPT
iptables -A INPUT -p tcp -s 10.10.5.55 --dport 44322 -j ACCEPT
iptables -A INPUT -p tcp -s 10.10.5.56 --dport 22 -j ACCEPT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
