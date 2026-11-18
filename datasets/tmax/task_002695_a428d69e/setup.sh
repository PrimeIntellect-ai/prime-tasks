#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    echo "PORT=8080\nDEBUG_LEVEL=0" > /app/corpus/clean/server1.conf
    echo "PORT=443\nDEBUG_LEVEL=0" > /app/corpus/clean/server2.conf

    echo "PORT=80\nSCRIPT=eval(echo 'hacked')" > /app/corpus/evil/hack.conf
    echo "LOG=../../../etc/shadow\nDEBUG_LEVEL=0" > /app/corpus/evil/traversal.conf
    echo "PORT=80" > "/app/corpus/evil/bad name .conf"

    touch /app/incident_report.wav

    cat << 'EOF' > /usr/local/bin/whisper
#!/bin/bash
echo "The archive key is omega."
EOF
    chmod +x /usr/local/bin/whisper

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
