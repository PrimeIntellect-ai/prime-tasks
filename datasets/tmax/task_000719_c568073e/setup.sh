#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "Our scanner detected a Cross-Site Scripting vulnerability. As a penetration tester, mitigate this by setting a strict Content Security Policy. Serve the S H A 2 5 6 hash of this audio file on an HTTP server on port eight zero eight zero."
    chmod -R 755 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
