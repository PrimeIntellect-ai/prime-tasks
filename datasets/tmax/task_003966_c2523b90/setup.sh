#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-traditional gawk
    pip3 install pytest

    mkdir -p /home/user/projects/src/ /home/user/projects/config/ /app/bash-serve/

    # Create project files
    echo "data" > /home/user/projects/src/main.c
    echo "old data" > /home/user/projects/src/main.c.bak
    echo "backup" > /home/user/projects/config/old.bak

    echo "PORT=9000\nSECRET_TOKEN=abc123xyz\nDEBUG=true" > /home/user/projects/config/settings.conf
    # Use printf to handle newlines correctly since echo -e behavior can vary
    printf "PORT=9000\nSECRET_TOKEN=abc123xyz\nDEBUG=true\n" > /home/user/projects/config/settings.conf
    printf "SECRET_TOKEN=dev_token\nLOG=1\n" > /home/user/projects/settings.conf

    # Create the vendored bash server with the deliberate error
    cat << 'EOF' > /app/bash-serve/serve.sh
#!/bin/bash
PORT=${PORT:-8080}
DIR=$1
if [ -z "$DIR" ]; then echo "Usage: $0 <dir>"; exit 1; fi
cd "$DIR" || exit 1
echo "Listening on $PORT..."
while true; do
  # Deliberate invalid flag -Z
  nc -l -Z -p $PORT -c 'read req; req_path=$(echo $req | awk "{print \$2}" | sed "s|^/||"); if [ -f "$req_path" ]; then echo -e "HTTP/1.1 200 OK\r\n\r\n"; cat "$req_path"; else echo -e "HTTP/1.1 404 Not Found\r\n\r\n"; fi'
done
EOF
    chmod +x /app/bash-serve/serve.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
