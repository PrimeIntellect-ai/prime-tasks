#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip netcat-openbsd gawk grep make
pip3 install pytest

mkdir -p /app/bash-webhook-1.0

cat << 'EOF' > /app/bash-webhook-1.0/Makefile
PREFIX=/usr/local
install:
	mkdir -p $(PREFIX)/bin
	cp webhook-server $(PREFIX)/bin/
	chmod +x $(PREFIX)/bin/webhook-server
EOF

cat << 'EOF' > /app/bash-webhook-1.0/webhook-server
#!/bin/bash
PORT=$1
ENDPOINT=$2
CMD=$3

echo "Listening on port $PORT for POST $ENDPOINT..."
while true; do
  nc -l -p $PORT -q 1 < <(
    read -r request_line
    HTTP_METHOD=$(echo "$request_line" | awk '{print $1}')
    HTTP_PATH=$(echo "$request_line" | awk '{print $2}')

    while read -r header; do
      [ "$header" == $'\r' ] && break
    done

    read -r body

    if [ "$REQUEST_METHOD" != "POST" ]; then
      echo -e "HTTP/1.1 405 Method Not Allowed\r\n\r\n"
      continue
    fi

    if [ "$HTTP_PATH" != "$ENDPOINT" ]; then
      echo -e "HTTP/1.1 404 Not Found\r\n\r\n"
      continue
    fi

    PROJECT=$(echo "$body" | grep -oP '"project":\s*"\K[^"]+')

    if [ -n "$PROJECT" ]; then
      $CMD "$PROJECT"
      echo -e "HTTP/1.1 200 OK\r\n\r\nSuccess"
    else
      echo -e "HTTP/1.1 400 Bad Request\r\n\r\n"
    fi
  )
done
EOF

chmod +x /app/bash-webhook-1.0/webhook-server

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
