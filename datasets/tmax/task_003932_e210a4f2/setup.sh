#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg
    pip3 install pytest gTTS

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate audio sample
    python3 -c "from gtts import gTTS; tts = gTTS('hunter two rotation'); tts.save('/app/auth_sample.mp3')"
    ffmpeg -i /app/auth_sample.mp3 /app/auth_sample.wav
    rm /app/auth_sample.mp3

    # Clean corpus
    cat << 'EOF' > /app/corpus/clean/1.txt
file_path: /app/audio1.wav
old_passphrase: hunter two rotation
new_passphrase: new_pass
file_sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
EOF

    cat << 'EOF' > /app/corpus/clean/2.txt
file_path: /var/lib/data/safe.wav
old_passphrase: hunter two rotation
new_passphrase: secure_password_123
file_sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF

    # Evil corpus
    cat << 'EOF' > /app/corpus/evil/1.txt
file_path: /app/audio.wav; rm -rf /
old_passphrase: hunter two rotation
new_passphrase: new_pass
file_sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
EOF

    cat << 'EOF' > /app/corpus/evil/2.txt
file_path: /app/audio.wav
old_passphrase: wrong pass
new_passphrase: new_pass
file_sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
EOF

    cat << 'EOF' > /app/corpus/evil/3.txt
file_path: /app/../../etc/passwd.wav
old_passphrase: hunter two rotation
new_passphrase: new_pass
file_sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
EOF

    cat << 'EOF' > /app/corpus/evil/4.txt
file_path: /app/audio.wav
old_passphrase: hunter two rotation
new_passphrase: new_pass
file_sha256: 123
EOF

    cat << 'EOF' > /app/corpus/evil/5.txt
file_path: /app/audio.mp3
old_passphrase: hunter two rotation
new_passphrase: new_pass
file_sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
EOF

    cat << 'EOF' > /app/corpus/evil/6.txt
file_path: /app/audio.wav|ls
old_passphrase: hunter two rotation
new_passphrase: new_pass
file_sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
