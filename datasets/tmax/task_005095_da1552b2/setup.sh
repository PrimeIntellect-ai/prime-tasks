#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y git nginx socat netcat-openbsd

    # Create directories
    mkdir -p /app/
    mkdir -p /opt/

    # Create dummy audio file
    echo "RIFF dummy audio data" > /app/transmission.wav

    # Create transcribe script
    cat << 'EOF' > /opt/transcribe.sh
#!/bin/bash
if [ "$1" == "/app/transmission.wav" ]; then
    echo "ECHO BRAVO CHARLIE ABORT SEQUENCE"
else
    echo "Unrecognized audio file."
    exit 1
fi
EOF
    chmod +x /opt/transcribe.sh

    # Create user
    useradd -m -s /bin/bash user || true

    # Adjust permissions
    chmod -R 777 /home/user
