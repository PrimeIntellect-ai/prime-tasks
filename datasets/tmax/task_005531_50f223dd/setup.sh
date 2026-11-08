#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/bin

echo "#!/bin/bash" > /home/user/bin/system_updater
echo "echo 'running'" >> /home/user/bin/system_updater

echo "#!/bin/bash" > /home/user/bin/backup_agent
echo "echo 'running'" >> /home/user/bin/backup_agent

echo "#!/bin/bash" > /home/user/bin/log_cleaner
echo "echo 'running'" >> /home/user/bin/log_cleaner

python3 -c '
import os
elf_content = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00"
elf_content += b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
elf_content += b"Some compiled garbage data here...\x00\x00\x00"
elf_content += b"Attempting exploit...\n\x00"
elf_content += b"/home/user/bin/backup_agent\x00"
elf_content += b"Decoy path: /home/user/bin/log_cleaner\x00" 
with open("/home/user/exploit.elf", "wb") as f:
    f.write(elf_content)
'

cat << 'EOF' > /home/user/traffic.log
GET / HTTP/1.1
Host: localhost:8080
User-Agent: curl/7.68.0
Accept: */*

GET /download_payload HTTP/1.1
Host: localhost:8080
User-Agent: custom-malware-agent/1.0
Cookie: session_id=12345; auth_token=super_secret_token_99; user=admin
Accept: application/octet-stream

EOF

chmod -R 777 /home/user
chmod 4755 /home/user/bin/backup_agent
