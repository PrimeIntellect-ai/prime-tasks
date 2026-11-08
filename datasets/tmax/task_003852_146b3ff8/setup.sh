#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev openssl gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create target environment file
    echo "PRODUCTION_SERVER_V2" > /home/user/target_environment.txt

    # Create firewall rules file
    cat << 'EOF' > /home/user/firewall_rules.txt
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -A OUTPUT -p tcp --dport 80 -j DROP
iptables -A OUTPUT -p tcp --dport 443 -j DROP
iptables -A OUTPUT -p udp --dport 1337 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j DROP
EOF

    # Create PIN hash (PIN is 7391)
    echo -n "7391" | md5sum | gawk '{print $1}' > /home/user/pin_hash.txt

    # Create Stage 2 encrypted file
    echo "REVERSE_SHELL_ACTIVATED" > /tmp/stage2_plain.txt
    openssl enc -aes-256-cbc -md md5 -pbkdf2 -iter 10000 -pass pass:7391 -in /tmp/stage2_plain.txt -out /home/user/stage2.enc
    rm /tmp/stage2_plain.txt

    chown -R user:user /home/user/
    chmod -R 777 /home/user
