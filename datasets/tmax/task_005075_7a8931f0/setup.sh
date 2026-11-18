#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak zip unzip python3-pocketsphinx
    pip3 install pytest SpeechRecognition

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/voicemail.wav "The archive password is alpha tango seven. Ensure the bastion SSH port is changed to 22022 and permit root login is set to no."

    # Create the evidence directories and files
    mkdir -p /tmp/evidence/evil /tmp/evidence/clean

    echo "http://example.com/login?next=http://evil.com" > /tmp/evidence/evil/payload1.txt
    echo "//attacker.com/bypass" > /tmp/evidence/evil/payload2.txt
    echo "https:evil.com" > /tmp/evidence/evil/payload3.txt
    echo "\/\/malicious.net" > /tmp/evidence/evil/payload4.txt
    echo "http://localhost@evil.com" > /tmp/evidence/evil/payload5.txt

    echo "/dashboard" > /tmp/evidence/clean/clean1.txt
    echo "/users/profile/settings" > /tmp/evidence/clean/clean2.txt
    echo "index.html" > /tmp/evidence/clean/clean3.txt
    echo "/login?success=true" > /tmp/evidence/clean/clean4.txt
    echo "/static/image.png" > /tmp/evidence/clean/clean5.txt

    # Zip and encrypt the evidence
    cd /tmp/evidence
    zip -r -P alphatango7 /app/evidence.zip evil clean

    # Clean up tmp
    rm -rf /tmp/evidence

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
