#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip socat gcc iputils-ping openssh-client
pip3 install pytest

mkdir -p /app/bash-admin-server/cgi-bin
mkdir -p /app/bash-admin-server/bin

cat << 'EOF' > /app/bash-admin-server/start.sh
#!/bin/bash
export SERVER_ROOT="/var/www/html"
socatt TCP-LISTEN:8000,reuseaddr,fork EXEC:"./cgi-handler.sh"
EOF
chmod +x /app/bash-admin-server/start.sh

cat << 'EOF' > /app/bash-admin-server/cgi-handler.sh
#!/bin/bash
read -r method uri protocol
uri=$(echo "$uri" | cut -d'?' -f1)
qs=$(echo "$uri" | cut -d'?' -f2-)
export QUERY_STRING="$qs"
script="/app/bash-admin-server$uri"
if [ -x "$script" ]; then
    "$script"
else
    echo -e "HTTP/1.1 404 Not Found\r\n\r\n"
fi
EOF
chmod +x /app/bash-admin-server/cgi-handler.sh

cat << 'EOF' > /app/bash-admin-server/cgi-bin/login.sh
#!/bin/bash
NEXT=$(echo "$QUERY_STRING" | grep -oP 'next=\K[^&]+')
echo -e "HTTP/1.1 302 Found\r\nLocation: $NEXT\r\n\r\n"
EOF
chmod +x /app/bash-admin-server/cgi-bin/login.sh

cat << 'EOF' > /app/bash-admin-server/cgi-bin/diag.sh
#!/bin/bash
IP=$(echo "$QUERY_STRING" | grep -oP 'ip=\K[^&]+' | tr -d '\r')
echo -e "HTTP/1.1 200 OK\r\n\r\n"
ping -c 1 $IP
EOF
chmod +x /app/bash-admin-server/cgi-bin/diag.sh

cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <string.h>
int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    if (strstr(argv[1], "CORP_SEC_2024_AUTH") != NULL) return 0;
    return 1;
}
EOF
gcc /tmp/validator.c -o /app/bash-admin-server/bin/key_validator
rm /tmp/validator.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
