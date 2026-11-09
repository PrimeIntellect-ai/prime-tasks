#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat make gawk jq
    pip3 install pytest

    mkdir -p /app/bash-conf-tracker

    cat << 'EOF' > /app/bash-conf-tracker/normalize.sh
#!/bin/bash
input="$1"
output="$2"

declare -A conf

while read -r line; do
    [ -z "$line" ] && continue
    key=$(echo "$line" | cut -d= -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
    val=$(echo "$line" | cut -d= -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
    conf["$key"]="$val"
done < "$input"

if [ -z "${conf[hostname]}" ]; then
    exit 1
fi

echo "{" > "$output"
first=1
for k in "${!conf[@]}"; do
    if [ $first -eq 0 ]; then
        echo "," >> "$output"
    fi
    echo -n "  \"$k\": \"${conf[$k]}\"" >> "$output"
    first=0
done
echo "" >> "$output"
echo "}" >> "$output"
exit 0
EOF
    chmod +x /app/bash-conf-tracker/normalize.sh

    cat << 'EOF' > /app/bash-conf-tracker/Makefile
install:
	mkdir -p /user/bin/
	cp *.sh /user/bin/
	chmod +x /user/bin/*.sh
EOF

    cat << 'EOF' > /app/bash-conf-tracker/start_server.sh
#!/bin/bash
PORT=$1
if [ -z "$PORT" ]; then PORT=9090; fi

cat << 'INNER_EOF' > /tmp/socat_handler.sh
#!/bin/bash
read request
method=$(echo "$request" | awk '{print $1}')
path=$(echo "$request" | awk '{print $2}')

while read -r header; do
    header=$(echo "$header" | tr -d '\r')
    [ -z "$header" ] && break
done

if [ "$method" = "POST" ] && [ "$path" = "/upload" ]; then
    cat > /tmp/payload.txt
    normalize.sh /tmp/payload.txt /tmp/out.json
    if [ $? -ne 0 ]; then
        echo -e "HTTP/1.1 400 Bad Request\r\n\r\nMissing hostname"
    else
        host=$(grep -o '"hostname": "[^"]*"' /tmp/out.json | cut -d'"' -f4)
        mkdir -p /home/user/configs
        cp /tmp/out.json "/home/user/configs/${host}.json"
        echo -e "HTTP/1.1 200 OK\r\n\r\nOK"
    fi
elif [ "$method" = "GET" ] && [[ "$path" == "/config?host="* ]]; then
    host=$(echo "$path" | cut -d'=' -f2)
    if [ -f "/home/user/configs/${host}.json" ]; then
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"
        cat "/home/user/configs/${host}.json"
    else
        echo -e "HTTP/1.1 404 Not Found\r\n\r\nNot Found"
    fi
else
    echo -e "HTTP/1.1 404 Not Found\r\n\r\nNot Found"
fi
INNER_EOF
chmod +x /tmp/socat_handler.sh

socat TCP4-LISTEN:${PORT},bind=127.0.0.1,fork,reuseaddr EXEC:/tmp/socat_handler.sh
EOF
    chmod +x /app/bash-conf-tracker/start_server.sh

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/configs
    chown -R user:user /home/user
    chmod -R 777 /home/user
