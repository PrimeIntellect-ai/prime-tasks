#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cron
pip3 install pytest gTTS

mkdir -p /app

cat << 'EOF' > /app/generate_audio.py
from gtts import gTTS
text = "Listen carefully to the new health check routing algorithm. Take the target IPv4 address and the latency in milliseconds. Add the second octet to the fourth octet. Multiply that sum by the latency. If the final value is strictly greater than ten thousand, output ALERT. Otherwise, output OK. End of message."
tts = gTTS(text)
tts.save("/app/net_instructions.wav")
EOF

python3 /app/generate_audio.py
rm /app/generate_audio.py

cat << 'EOF' > /app/oracle_health_eval
#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    ip = sys.argv[1]
    latency = int(sys.argv[2])

    octets = ip.split('.')
    if len(octets) != 4:
        sys.exit(1)

    val = (int(octets[1]) + int(octets[3])) * latency

    if val > 10000:
        print("ALERT")
    else:
        print("OK")

if __name__ == "__main__":
    main()
EOF

chmod +x /app/oracle_health_eval

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
