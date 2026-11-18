#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-traditional
    pip3 install pytest

    mkdir -p /app/raw_data
    mkdir -p /app/organized_data
    mkdir -p /app/bash-serve-v1.2

    # Generate raw data
    cat << 'EOF' > /tmp/gen_data.sh
#!/bin/bash
categories=("syslogs" "metrics" "traces")
for i in {1..50}; do
  cat_idx=$((i % 3))
  cat=${categories[$cat_idx]}
  ts=$((1680000000 + i))
  file="/app/raw_data/dump_${i}.dat"
  echo "CATEGORY: ${cat}" > "$file"
  echo "TIMESTAMP: ${ts}" >> "$file"
  echo "PAYLOAD data line 1" >> "$file"
  echo "PAYLOAD data line 2" >> "$file"
done
EOF
    chmod +x /tmp/gen_data.sh
    /tmp/gen_data.sh

    # Vendored bash-serve
    cat << 'EOF' > /app/bash-serve-v1.2/serve.sh
#!/bin/bash
PORT=$1
DIR="/tmp/www" # BUG: Should be ${BASE_DIR:-/tmp/www}

rm -f /tmp/serve_fifo
mkfifo /tmp/serve_fifo

while true; do
  cat /tmp/serve_fifo | nc -l -p $PORT > /tmp/serve_req

  req_line=$(head -n 1 /tmp/serve_req | tr -d '\r')
  method=$(echo $req_line | awk '{print $1}')
  path=$(echo $req_line | awk '{print $2}')

  auth_header=$(grep -i "Authorization:" /tmp/serve_req | cut -d':' -f2- | sed -e 's/^[[:space:]]*//' | tr -d '\r')

  # BUG: Weak token check
  if [[ "$auth_header" == *"Bearer"* ]]; then
    target_file="${DIR}${path}"
    if [ -f "$target_file" ]; then
      echo -e "HTTP/1.1 200 OK\r\nContent-Length: $(stat -c%s "$target_file")\r\n\r" > /tmp/serve_fifo
      cat "$target_file" > /tmp/serve_fifo
    else
      echo -e "HTTP/1.1 404 Not Found\r\n\r\nFile not found." > /tmp/serve_fifo
    fi
  else
    echo -e "HTTP/1.1 401 Unauthorized\r\n\r\nInvalid token." > /tmp/serve_fifo
  fi
done
EOF
    chmod +x /app/bash-serve-v1.2/serve.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
