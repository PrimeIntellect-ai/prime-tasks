#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/locales/

cat << 'EOF' > /home/user/locales/es.json
{
  "hello": "hola",
  "welcome": "bienvenido"
}
EOF

cat << 'EOF' > /home/user/locales/fr.json
{
  "hello": "bonjour"
}
EOF

cat << 'EOF' > /home/user/missing_strings.log
2023-10-05 09:15:30 | es | bye | goodbye
2023-10-05 09:45:10 | es | thanks | thank you
2023-10-05 09:50:00 | fr | bye | goodbye
2023-10-05 10:05:00 | es | help | help me
2023-10-05 10:12:00 | es | bye | goodbye
2023-10-05 10:30:00 | fr | help | help me
EOF

chmod -R 777 /home/user
