#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git socat netcat-openbsd gawk
    pip3 install pytest

    mkdir -p /app/bash-http-server
    cd /app/bash-http-server
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > server.sh
#!/bin/bash
PORT=9090

function handle_request() {
    read request
    request=$(echo "$request" | tr -d '\r')
    method=$(echo "$request" | awk '{print $1}')
    path=$(echo "$request" | awk '{print $2}')

    while read header; do
        header=$(echo "$header" | tr -d '\r')
        if [ -z "$header" ]; then
            break
        fi
        if [[ "$header" == User-Agent:* ]]; then
            HTTP_USER_AGENT="${header#User-Agent: }"
        fi
    done

    if [ "$path" == "/" ]; then
        echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
    elif [ "$path" == "/compute" ]; then
        # COMPUTE_LOGIC
        echo -e "HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\nCOMPUTE"
    else
        echo -e "HTTP/1.1 404 Not Found\r\n\r\n"
    fi
}

export -f handle_request

socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"bash -c handle_request"
EOF
    chmod +x server.sh
    git add server.sh
    git commit -m "Initial commit"

    for i in $(seq 2 200); do
        if [ $i -eq 150 ]; then
            sed -i '/# COMPUTE_LOGIC/a \        if [[ "$HTTP_USER_AGENT" == *"fuzz-crash"* ]]; then\n            ( while true; do sleep 0.1; done ) &\n        fi' server.sh
            git add server.sh
            git commit -m "Update compute logic"
        else
            echo "# Comment $i" >> server.sh
            git add server.sh
            git commit -m "Minor update $i"
        fi
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
