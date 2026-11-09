#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        socat \
        jq \
        ffmpeg \
        espeak \
        curl \
        netcat-traditional

    pip3 install pytest

    mkdir -p /home/user/pr
    cat << 'EOF' > /home/user/pr/server.sh
#!/bin/bash
echo "Starting broken webhook server..."
while true; do
    nc -l -p 8080 -c '
        read request
        read headers
        read payload
        # Vulnerable to command injection!
        eval "echo Build triggered for $payload"
    '
done
EOF
    chmod +x /home/user/pr/server.sh

    mkdir -p /app
    espeak -w /app/auth_token.wav "blue flamingo dances brightly"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
