#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/safe_uploads
    chmod 755 /app/safe_uploads

    # Create the initial config
    cat << 'EOF' > /app/auth_config.env
ADMIN_TOKEN=dex972
EOF
    chmod 644 /app/auth_config.env

    # Create the vulnerable upload handler template
    cat << 'EOF' > /app/upload_processor.sh
#!/bin/bash
source /app/auth_config.env

filename="default.wav"
while read -r line; do
    line=$(echo "$line" | tr -d '\r\n')
    if [ -z "$line" ]; then
        break
    fi
    if [[ "$line" == X-Upload-Filename:* ]]; then
        filename=$(echo "$line" | cut -d ' ' -f 2)
    fi
done

cat > "/app/safe_uploads/$filename"
echo "HTTP/1.1 200 OK"
EOF
    chmod 755 /app/upload_processor.sh

    # Generate the intercepted audio file
    espeak -w /app/intercepted_voice_auth.wav "The backup access token is delta echo x-ray nine seven two"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
