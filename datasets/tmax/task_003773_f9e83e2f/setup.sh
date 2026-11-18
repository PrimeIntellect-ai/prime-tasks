#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect socat openssl tar gawk
pip3 install pytest

mkdir -p /home/user/www
echo "Hello Secure World" > /home/user/www/index.html

mkdir -p /home/user/config_template
echo "serve_dir /var/www" > /home/user/config_template/bashttpd.conf

mkdir -p /app/bashttpd
cat << 'EOF' > /app/bashttpd/bashttpd
#!/bin/bash
RSPONSE="HTTP/1.1 200 OK\r\n"
while read line; do
  line=$(echo "$line" | tr -d '\r')
  if [ -z "$line" ]; then
    break
  fi
  if echo "$line" | grep -q "^GET "; then
    FILE=$(echo "$line" | awk '{print $2}')
    if [ "$FILE" = "/" ]; then FILE="/index.html"; fi
  fi
done
echo -en "$RESPONSE"
echo -en "Content-Type: text/html\r\n\r\n"
cat /home/user/www$FILE 2>/dev/null || echo "Not found"
EOF
chmod +x /app/bashttpd/bashttpd

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
