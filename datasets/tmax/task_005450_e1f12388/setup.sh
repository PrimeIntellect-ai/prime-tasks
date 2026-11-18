#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest openai-whisper gTTS

    mkdir -p /app

    # Generate the voicemail.wav
    gtts-cli "Listen carefully to the capacity allocation rules. Your script must first resolve the absolute path of the input, following all symlinks. Rule one: If the fully resolved path contains the exact string 'qemu', you must assign it to zone 'hypervisor', timezone 'Etc/UTC', and locale 'en_US.UTF-8'. Rule two: If the resolved path does not contain 'qemu' but contains the string 'cicd', assign it to zone 'pipeline', timezone 'America/New_York', and locale 'en_US.UTF-8'. Rule three: For any other path, assign it to zone 'standard', timezone 'Europe/Berlin', and locale 'de_DE.UTF-8'. The output must be a single line formatted exactly like this, in all uppercase keys: ZONE={zone} TZ={timezone} LOCALE={locale}." --output /app/voicemail.mp3
    ffmpeg -i /app/voicemail.mp3 /app/voicemail.wav
    rm /app/voicemail.mp3

    # Create oracle script
    cat << 'EOF' > /app/oracle_allocate
#!/bin/bash
TARGET=$(readlink -m "$1")
if [[ "$TARGET" == *"qemu"* ]]; then
    echo "ZONE=hypervisor TZ=Etc/UTC LOCALE=en_US.UTF-8"
elif [[ "$TARGET" == *"cicd"* ]]; then
    echo "ZONE=pipeline TZ=America/New_York LOCALE=en_US.UTF-8"
else
    echo "ZONE=standard TZ=Europe/Berlin LOCALE=de_DE.UTF-8"
fi
EOF
    chmod +x /app/oracle_allocate

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
