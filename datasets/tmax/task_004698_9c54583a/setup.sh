#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip acl espeak systemd
    pip3 install pytest pexpect SpeechRecognition pydub

    mkdir -p /app
    cat << 'EOF' > /app/init_capacity_db.sh
#!/bin/bash
read -p "Enter CPU threshold: " thresh
read -p "Enter admin PIN: " pin
if [ "$pin" == "700700" ] && [ "$thresh" == "85" ]; then
    echo "{\"cpu_threshold\": 85, \"source\": \"init_db\"}" > /home/user/capacity_config.json
    echo "DB Initialized."
else
    echo "Auth failed or bad threshold."
    exit 1
fi
EOF
    chmod 700 /app/init_capacity_db.sh

    espeak -w /app/capacity_memo.wav "The new CPU threshold is eighty-five percent. Bind the capacity planner API to port eight one two three."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
