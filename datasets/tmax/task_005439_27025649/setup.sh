#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg gawk
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "The backdoor keyword is OmegaProtocol2024"

    mkdir -p /app/auth_keys

    cat << 'EOF' > /app/auth_service.sh
#!/bin/bash
# Obfuscated authentication service logic
# Relies on /app/auth_keys/ permissions
FAIL_COUNT=$(grep -c "FAILED_LOGIN" /var/log/auth.log)
if [ "$FAIL_COUNT" -eq 3 ] && [[ "$PAYLOAD" == *"OmegaProtocol2024"* ]]; then
    echo "Backdoor activated"
fi
EOF
    chmod +x /app/auth_service.sh

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    for i in $(seq 1 5); do
        cat << EOF > /app/corpus/clean/log${i}.txt
2024-01-01T12:00:00 192.168.1.1 user1 FAILED_LOGIN -
2024-01-01T12:00:05 192.168.1.1 user1 SUCCESS_LOGIN -
2024-01-01T12:00:10 192.168.1.1 user1 EXECUTE ls
EOF
    done

    for i in $(seq 1 5); do
        cat << EOF > /app/corpus/evil/log${i}.txt
2024-01-01T12:00:00 10.0.0.1 attacker FAILED_LOGIN -
2024-01-01T12:00:05 10.0.0.1 attacker FAILED_LOGIN -
2024-01-01T12:00:10 10.0.0.1 attacker FAILED_LOGIN -
2024-01-01T12:00:15 10.0.0.1 attacker EXECUTE OmegaProtocol2024
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
