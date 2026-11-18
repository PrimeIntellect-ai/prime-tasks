#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/messy_data.log
System booted at [2023-01-01 00:00:00].
User admin logged in from root@localhost. [2023-10-15 09:15:22]
Error: missing dependency.
[2023-10-14 08:30:00] alert triggered for admin@server.local - CPU high
Invalid line with two emails a@b.com and c@d.com [2023-10-15 10:00:00]
[2023-10-16 11:11:11] Support ticket opened by user.test@enterprise.com.
Random text.
User admin logged in from root@localhost. [2023-10-15 09:15:22]
[2022-12-31 23:59:59] new_year@party.org joined the server.
EOF

chmod -R 777 /home/user
