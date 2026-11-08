#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg gawk coreutils

# Install pytest
pip3 install --no-cache-dir pytest

# Install CPU-only PyTorch to save time and space, then whisper
pip3 install --no-cache-dir torch torchaudio --index-url https://download.pytorch.org/whl/cpu
pip3 install --no-cache-dir openai-whisper

mkdir -p /app

# Generate the audio file
espeak -w /app/network_log.wav "Alice knows Bob. Bob knows Charlie. Charlie knows David. Alice knows Eve. Eve knows Frank. Frank knows Bob. Gina knows Harry. Harry knows Alice."

# Create the oracle script
cat << 'EOF' > /app/oracle.sh
#!/bin/bash
NODE=$1
EDGES="Alice Bob
Bob Charlie
Charlie David
Alice Eve
Eve Frank
Frank Bob
Gina Harry
Harry Alice"

HOP1=$(echo "$EDGES" | awk -v n="$NODE" '{if($1==n) print $2; else if($2==n) print $1}')

if [ -z "$HOP1" ]; then
    echo "NONE"
    exit 0
fi

HOP2=""
for h1 in $HOP1; do
    HOP2="$HOP2 $(echo "$EDGES" | awk -v n="$h1" '{if($1==n) print $2; else if($2==n) print $1}')"
done

EXCLUDE=$(echo -e "$NODE\n$HOP1" | tr ' ' '\n' | sort -u)
RESULT=$(echo "$HOP2" | tr ' ' '\n' | grep -v '^$' | sort -u | grep -vxFf <(echo "$EXCLUDE") | paste -sd ' ')

if [ -z "$RESULT" ]; then
    echo "NONE"
else
    echo "$RESULT"
fi
EOF

chmod +x /app/oracle.sh

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
