#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the voicemail audio file
    espeak -w /app/voicemail.wav "Hello, this is the compliance team. The new audit trail processor needs to read JSON lines from standard input. For each line, output a CSV row with exactly four columns. First, the IP address, but replace the entire last octet with the word REDACTED. Second, evaluate the risk: if privesc_risk is true, output ESCALATION. If privesc_risk is false but cve_score is 7.0 or higher, output VULN. Otherwise, output CLEAN. Third, output the port number in lowercase hexadecimal, prefixed with zero x. Fourth, output the service name in all uppercase. Thank you."

    # Create the oracle script
    cat << 'EOF' > /app/oracle_normalizer.py
#!/usr/bin/env python3
import sys
import json

def process_line(line):
    try:
        data = json.loads(line.strip())

        # Rule 1: IP address with last octet masked as REDACTED
        ip_parts = data['ip_address'].split('.')
        masked_ip = f"{ip_parts[0]}.{ip_parts[1]}.{ip_parts[2]}.REDACTED"

        # Rule 2: Risk evaluation
        if data.get('privesc_risk') is True:
            risk = "ESCALATION"
        elif data.get('cve_score', 0.0) >= 7.0:
            risk = "VULN"
        else:
            risk = "CLEAN"

        # Rule 3: Hex port
        hex_port = hex(data['port'])

        # Rule 4: Uppercase service
        service_upper = data['service'].upper()

        return f"{masked_ip},{risk},{hex_port},{service_upper}"
    except Exception as e:
        return ""

if __name__ == '__main__':
    for line in sys.stdin:
        if not line.strip():
            continue
        out = process_line(line)
        if out:
            print(out)
EOF

    chmod +x /app/oracle_normalizer.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
