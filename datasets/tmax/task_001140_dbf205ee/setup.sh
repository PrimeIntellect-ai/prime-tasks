#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip make socat openssl curl gawk
pip3 install pytest

mkdir -p /app/bash-web-auditor
mkdir -p /home/user/bin

cat << 'EOF' > /app/bash-web-auditor/auditor.sh
#!/bin/bash
read request
token=""
while read -r line; do
    line=$(echo "$line" | tr -d '\r\n')
    [ -z "$line" ] && break
    if echo "$line" | grep -qi "^Authorization: Bearer"; then
        token=$(echo "$line" | awk '{print $3}')
    fi
done
echo "Audit request received with token: $token" >> /app/audit.log
/home/user/bin/worker.sh "$token" &

echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nSuccess"
EOF

cat << 'EOF' > /app/bash-web-auditor/worker.sh
#!/bin/bash
sleep 2
EOF

cat << 'EOF' > /app/bash-web-auditor/Makefile
install:
	mkdir -p /home/user/bin
	cp -z auditor.sh /home/user/bin/
	cp worker.sh /home/user/bin/
	chmod +x /home/user/bin/*.sh
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /app/bash-web-auditor
chown -R user:user /home/user
chmod -R 777 /app
chmod -R 777 /home/user
