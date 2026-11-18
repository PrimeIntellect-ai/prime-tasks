#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /app/audio
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate audio file
    espeak -w /app/audio/override.wav "The override code is ALFA-TANGO-7 and the time is 19:45."

    # Create clean logs
    cat << 'EOF' > /app/corpora/clean/log1.txt
[2023-10-25 10:00:00] USER1 LOGIN "Success"
[2023-10-25 10:00:02] USER1 ACTION "Do something"
[2023-10-25 10:00:05] USER2 LOGIN "Success"
EOF

    cat << 'EOF' > /app/corpora/clean/log2.txt
[2023-10-25 11:00:00] USER3 LOGIN "Success"
[2023-10-25 11:00:11] USER3 LOGOUT "Bye"
EOF

    # Create evil logs
    # 1. Contains override code
    cat << 'EOF' > /app/corpora/evil/evil_code.txt
[2023-10-25 10:00:00] USER1 LOGIN "Success"
[2023-10-25 10:00:05] USER1 ACTION "ALFA-TANGO-7"
EOF

    # 2. Rapid bursting (>4 commands in 1s)
    cat << 'EOF' > /app/corpora/evil/evil_burst.txt
[2023-10-25 10:00:00] USER1 ACTION "1"
[2023-10-25 10:00:00] USER1 ACTION "2"
[2023-10-25 10:00:00] USER1 ACTION "3"
[2023-10-25 10:00:00] USER1 ACTION "4"
[2023-10-25 10:00:00] USER1 ACTION "5"
EOF

    # 3. Gap > 10s followed by SYSTEM_REBOOT
    cat << 'EOF' > /app/corpora/evil/evil_reboot.txt
[2023-10-25 10:00:00] USER1 ACTION "Normal"
[2023-10-25 10:00:15] USER1 SYSTEM_REBOOT "Restarting"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
