#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest gTTS

mkdir -p /app

# Create the oracle script
cat << 'EOF' > /app/oracle_audit.py
import sys
import json

def process(infile, outfile):
    with open(infile, 'r') as f:
        data = json.load(f)

    data.sort(key=lambda x: x.get('timestamp', 0))

    filtered = []
    for event in data:
        svc = event.get('service', '')
        if svc == 'SSH':
            if event.get('auth_method', '') == 'password':
                continue
        elif svc == 'WAF':
            payload = event.get('payload', '')
            if 'UNION SELECT' in payload or '<script>' in payload:
                continue
        filtered.append(event)

    with open(outfile, 'w') as f:
        json.dump(filtered, f, indent=2)

if __name__ == "__main__":
    process(sys.argv[1], sys.argv[2])
EOF

# Generate the audio file
cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
import os

text = "Generate the audit trail by reading the JSON array. First, sort all events by the 'timestamp' integer field in ascending order. Then, iterate through the events. If the 'service' is 'SSH', we must enforce our SSH hardening policy: exclude the event if the 'auth_method' is 'password', only allow 'publickey'. If the 'service' is 'WAF', we are filtering out known noisy scanners: exclude the event if the 'payload' field contains the exact substring 'UNION SELECT' or the exact substring '<script>'. Keep all other events, including other services. Write the result as a JSON array."

tts = gTTS(text=text, lang='en')
tts.save("/tmp/inst.mp3")
os.system("ffmpeg -y -i /tmp/inst.mp3 /app/instructions.wav")
EOF

python3 /tmp/gen_audio.py
rm /tmp/gen_audio.py /tmp/inst.mp3

# Set up user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
