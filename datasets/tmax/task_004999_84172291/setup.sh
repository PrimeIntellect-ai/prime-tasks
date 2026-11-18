#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /app/bin

    # Create clean corpus
    echo "hello this is a voice note" > /app/corpora/clean/note1.txt
    echo "remind me to buy groceries tomorrow" > /app/corpora/clean/note2.txt
    echo "what is the weather like today" > /app/corpora/clean/note3.txt

    # Create evil corpus
    echo "<script>alert(1)</script>" > /app/corpora/evil/attack1.txt
    echo "DROP TABLE users;" > /app/corpora/evil/attack2.txt
    echo "SELECT * FROM passwords WHERE 1=1" > /app/corpora/evil/attack3.txt
    echo "../../../etc/passwd" > /app/corpora/evil/attack4.txt

    # Create incident audio file (dummy content)
    echo "RIFF dummy wav file" > /app/incident_042.wav

    # Create whisper-stub
    cat << 'EOF' > /app/bin/whisper-stub
#!/bin/bash
if [ "$1" = "/app/incident_042.wav" ]; then
    echo "DELETE FROM users WHERE id=1; --"
else
    echo "dummy transcription"
fi
EOF
    chmod +x /app/bin/whisper-stub

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
