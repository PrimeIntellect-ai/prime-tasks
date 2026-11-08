#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make socat curl sudo
    pip3 install pytest

    mkdir -p /app/bash-http-scheduler

    cat << 'EOF' > /app/bash-http-scheduler/Makefile
run:
	socat TCP4-LISTEN:8080,reuseaddr,fork EXEC:./server.sh
EOF

    cat << 'EOF' > /app/bash-http-scheduler/server.sh
#!/bin/bash
read -r request
while read -r line; do
  line=$(echo "$line" | tr -d '\r')
  [ -z "$line" ] && break
done
read -n 1024 body || true

TIME=$(echo "$body" | grep -o 'time=[^&]*' | cut -d= -f2)
JOB=$(echo "$body" | grep -o 'job=[^&]*' | cut -d= -f2)

OUT=$(./process.sh "$TIME" "$JOB")
STATUS=$?

if [ $STATUS -eq 0 ]; then
  echo -ne "HTTP/1.1 200 OK\r\nContent-Length: ${#OUT}\r\n\r\n$OUT"
else
  echo -ne "HTTP/1.1 400 Bad Request\r\nContent-Length: ${#OUT}\r\n\r\n$OUT"
fi
EOF

    cat << 'EOF' > /app/bash-http-scheduler/process.sh
#!/bin/bash
TIME=$1
JOB=$2

if [ -z "$TIME" ]; then
  echo "Error: missing time"
  exit 1
fi

TARGET_TS=$(date -d "$TIME" +%s)
NOW_TS=$(date -u +%s)
DELAY=$((TARGET_TS - NOW_TS))

if [ "$DELAY" -lt 0 ]; then
  echo "Error: Time in past"
  exit 1
fi

if [ "$DELAY" -ge 86400 ]; then
  echo "Error: Too far"
  exit 1
fi

echo "$TARGET_TS"
EOF

    chmod +x /app/bash-http-scheduler/server.sh
    chmod +x /app/bash-http-scheduler/process.sh

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user
    chmod 0440 /etc/sudoers.d/user

    chown -R user:user /app
    chmod -R 777 /home/user
