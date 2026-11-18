#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq espeak
    pip3 install pytest SpeechRecognition

    mkdir -p /app

    cat << 'EOF' > /app/oracle_mapper.sh
#!/bin/bash
jq -r '.[] | select(.confidence >= 0.80) | "\(.file_id) => \(.status | ascii_upcase)_\(.timestamp).dat"'
EOF
    chmod +x /app/oracle_mapper.sh

    espeak -w /app/voice_memo.wav "To process the telemetry logs, read the JSON stream. For each object, check the confidence field. If confidence is less than point eight zero, completely ignore the record. Otherwise, print the file_id followed by a space, an equals sign, a right angle bracket, and a space. Then construct the new name: the status in all uppercase, an underscore, the timestamp, and finally the extension dot dat."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
