#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "To fix the build, the checksum algorithm must take the input integer, multiply it by seventeen, add forty two, and finally return the result modulo two hundred fifty six."

    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
echo $(( ($1 * 17 + 42) % 256 ))
EOF
    chmod +x /app/oracle.sh

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/checksum.sh
#!/bin/bash
# CORRUPTED FILE
echo "0xDEADBEEF"
EOF
    chmod +x /home/user/checksum.sh

    chmod -R 777 /home/user
    chmod -R 777 /app
