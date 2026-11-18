#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip unzip espeak
pip3 install pytest

mkdir -p /app/hidden_eval/evil /app/hidden_eval/clean
mkdir -p /tmp/corpus/traffic/evil /tmp/corpus/traffic/clean

# Generate the audio file containing the passphrase
espeak -w /app/voicenote.wav "The new encryption key for the payload drop is hunter two omega nine."

# Create training corpora
echo "/?id=1 UNION SELECT 0x61646d696e   --" > /tmp/corpus/traffic/evil/payload1.txt
echo "SELECT name FROM items WHERE id=2 UNION SELECT 0x123456      --" > /tmp/corpus/traffic/evil/payload2.txt
echo "/?id=1" > /tmp/corpus/traffic/clean/payload1.txt
echo "SELECT * FROM users WHERE id=1" > /tmp/corpus/traffic/clean/payload2.txt

# Create the encrypted zip archive
cd /tmp/corpus
zip -r -P hunter2omega9 /app/traffic_dump.zip traffic/

# Create hidden evaluation corpora
echo "/?id=5 UNION SELECT 0x000000   --" > /app/hidden_eval/evil/eval1.txt
echo "SELECT * FROM x UNION SELECT 0xabcdef      --" > /app/hidden_eval/evil/eval2.txt
echo "/?id=5" > /app/hidden_eval/clean/eval1.txt
echo "SELECT * FROM x" > /app/hidden_eval/clean/eval2.txt

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
