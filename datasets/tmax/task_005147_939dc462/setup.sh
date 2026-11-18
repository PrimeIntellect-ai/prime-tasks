#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest passlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sshd_config_test
# SSH config
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
X11Forwarding no
EOF

    cat << 'EOF' > /home/user/iptables_export.txt
-P INPUT ACCEPT
-P FORWARD DROP
-P OUTPUT ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 8080 -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

    cat << 'EOF' > /home/user/wordlist.txt
admin
password
qwerty
dragon
sunshine
iloveyou
charlie
EOF

    python3 -c "
import crypt
print('root:*::::::')
print('appuser:' + crypt.crypt('dragon', crypt.mksalt(crypt.METHOD_SHA512)) + ':18000:0:99999:7:::')
print('dev:' + crypt.crypt('qwerty', crypt.mksalt(crypt.METHOD_SHA512)) + ':18000:0:99999:7:::')
" > /home/user/shadow_test

    chmod 644 /home/user/sshd_config_test /home/user/iptables_export.txt /home/user/wordlist.txt /home/user/shadow_test
    chmod -R 777 /home/user
