#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest gTTS

    mkdir -p /app
    mkdir -p /opt/oracle

    # Create oracle script
    cat << 'EOF' > /opt/oracle/log_filter_oracle.sh
#!/bin/bash
awk -F',' '$2 == "billing-svc" && $4 > 400 {print $3}'
EOF
    chmod +x /opt/oracle/log_filter_oracle.sh

    # Create audio file
    cat << 'EOF' > /app/generate_audio.py
from gtts import gTTS

text = "Alert configuration update. We need to monitor the new billing service. Write a filter script that reads lines from standard input. Each line is comma separated: timestamp, service name, ip address, and response time in milliseconds. Print only the ip address for lines where the service name is exactly billing-svc and the response time is strictly greater than four hundred."

tts = gTTS(text=text, lang='en')
tts.save("/app/voicemail_SRE.wav")
EOF
    python3 /app/generate_audio.py
    rm /app/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
