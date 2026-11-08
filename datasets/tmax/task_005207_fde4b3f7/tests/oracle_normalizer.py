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
