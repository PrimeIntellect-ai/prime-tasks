#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak ffmpeg
    pip3 install pytest SpeechRecognition pydub

    mkdir -p /app/.hidden

    # Create the legacy auth binary
    cat << 'EOF' > /tmp/auth.c
#include <stdio.h>
int main() {
    const char* password = "crimson_typhoon_99";
    printf("Legacy auth initialized.\n");
    return 0;
}
EOF
    gcc /tmp/auth.c -o /app/legacy_auth
    rm /tmp/auth.c

    # Create the audio file
    espeak -w /app/incident_audio.wav "The master password is crimson_typhoon_99"

    # Create the audit logs and expected logs
    cat << 'EOF' > /tmp/gen_logs.py
import random
random.seed(42)
with open('/app/audit_logs.txt', 'w') as f1, open('/app/.hidden/expected_logs.txt', 'w') as f2:
    for i in range(5000):
        if random.random() < 0.05:
            line = f"2023-10-01 12:00:{i%60:02d} - ERROR - Failed login attempt using credential: crimson_typhoon_99\n"
            line_expected = f"2023-10-01 12:00:{i%60:02d} - ERROR - Failed login attempt using credential: [REDACTED]\n"
        elif random.random() < 0.05:
            line = f"2023-10-01 12:01:{i%60:02d} - INFO - User admin updated password to crimson_typhoon_99 successfully.\n"
            line_expected = f"2023-10-01 12:01:{i%60:02d} - INFO - User admin updated password to [REDACTED] successfully.\n"
        else:
            line = f"2023-10-01 12:02:{i%60:02d} - INFO - System health check passed. Load average: {random.random():.2f}\n"
            line_expected = line

        f1.write(line)
        f2.write(line_expected)
EOF
    python3 /tmp/gen_logs.py
    rm /tmp/gen_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
    chmod 700 /app/.hidden
    chmod 600 /app/.hidden/expected_logs.txt
