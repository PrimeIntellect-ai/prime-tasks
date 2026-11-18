#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

mkdir -p /app

# Create the oracle script
cat << 'EOF' > /app/oracle_eval
#!/bin/bash
if [ "$#" -ne 3 ]; then
    echo "ERROR"
    exit 0
fi

INTERFACE="$1"
STATUS="$2"
LATENCY="$3"

if [[ "$INTERFACE" == vpn* ]]; then
    echo "IGNORE"
elif [[ "$INTERFACE" == "eth0" && "$LATENCY" -eq 0 ]]; then
    echo "ERROR"
elif [[ "$STATUS" == "DOWN" ]]; then
    echo "FAILOVER"
elif [[ "$LATENCY" -gt 50 ]]; then
    echo "FAILOVER"
elif [[ "$STATUS" != "UP" && "$STATUS" != "DOWN" ]]; then
    echo "ERROR"
else
    echo "OK"
fi
EOF
chmod +x /app/oracle_eval

# Generate the audio file
espeak -w /app/architect_notes.wav "Hello, this is the architect. For the new deployment health script, follow these rules exactly in order. First, if the interface name begins with the letters v p n, always return IGNORE. Second, if the interface is exactly e t h 0 and the latency is exactly 0, return ERROR. Third, if the status is DOWN, return FAILOVER. Fourth, if latency is strictly greater than 50, return FAILOVER. In all other valid cases, return OK."

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
