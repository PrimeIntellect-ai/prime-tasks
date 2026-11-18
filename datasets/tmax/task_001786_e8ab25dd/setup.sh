#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc openssl
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data /home/user/jail/bin /home/user/certs

echo "User Alice paid with 1234567812345678 today. Valid until 12/25. Another user Bob used 1111222233334444 for his transaction. Order 98765 is complete." > /home/user/data/transactions.log
printf "22\n8080\n443\n3306\n" > /home/user/data/open_ports.txt

touch /home/user/jail/bin/ls
touch /home/user/jail/bin/cat
touch /home/user/jail/bin/sneaky_suid
touch /home/user/jail/bin/backdoor

chmod -R 777 /home/user
chmod 4755 /home/user/jail/bin/sneaky_suid
chmod 4755 /home/user/jail/bin/backdoor
