#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata
    pip3 install pytest pytz

    mkdir -p /app

    # Create dummy voicemail file
    echo "RIFF....WAVEfmt ....." > /app/voicemail.wav

    # Create mock whisper command to avoid heavy installation and timeouts
    cat << 'EOF' > /usr/local/bin/whisper
#!/bin/bash
echo "Update for the log parser. Ensure the script operates in the Pacific/Fiji timezone. The input log lines will be separated by a pipe character. The first field is an integer Unix timestamp. Convert it to an ISO 8601 string in the Pacific/Fiji timezone. The second field is the severity level, which must be forced to lowercase. The third field is the message. Output a JSON object with keys 'timestamp', 'level', and 'message'. If a line does not have exactly three pipe-separated fields, or if the timestamp is not a valid integer, you must catch the error and output exactly {\"error\": \"malformed\"}. That is all."
EOF
    chmod +x /usr/local/bin/whisper

    # Create oracle parser
    cat << 'EOF' > /app/oracle_parser
#!/usr/bin/env python3
import sys
import json
from datetime import datetime
import pytz

def main():
    input_text = sys.stdin.read().strip('\n')
    parts = input_text.split('|')
    if len(parts) != 3:
        print(json.dumps({"error": "malformed"}))
        return

    try:
        ts = int(parts[0])
        tz = pytz.timezone('Pacific/Fiji')
        dt = datetime.fromtimestamp(ts, tz)
        iso = dt.isoformat()

        level = parts[1].lower()
        msg = parts[2]

        print(json.dumps({
            "timestamp": iso,
            "level": level,
            "message": msg
        }))
    except Exception:
        print(json.dumps({"error": "malformed"}))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_parser

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
