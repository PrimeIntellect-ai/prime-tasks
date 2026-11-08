#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq binutils
    pip3 install pytest

    mkdir -p /home/user

    # 1. Create the fake implant binary with a hardcoded C2 domain
    cat << 'EOF' > /home/user/implant.c
#include <stdio.h>
int main() {
    char *c2 = "https://sys-update-c2.xyz/api/register";
    printf("Starting...\n");
    return 0;
}
EOF
    gcc /home/user/implant.c -o /home/user/implant
    rm /home/user/implant.c

    # 2. Create the CSP violations log
    cat << 'EOF' > /home/user/csp_violations.jsonl
{"source_ip": "192.168.1.50", "timestamp": "2023-10-25T10:00:00Z", "csp-report": {"document-uri": "http://internal.corp", "blocked-uri": "https://sys-update-c2.xyz/api/register", "violated-directive": "connect-src"}}
{"source_ip": "192.168.1.102", "timestamp": "2023-10-25T10:05:00Z", "csp-report": {"document-uri": "http://internal.corp/admin", "blocked-uri": "https://analytics-tracker.com/event", "violated-directive": "connect-src"}}
{"source_ip": "192.168.1.50", "timestamp": "2023-10-25T10:10:00Z", "csp-report": {"document-uri": "http://internal.corp", "blocked-uri": "https://sys-update-c2.xyz/api/register", "violated-directive": "connect-src"}}
{"source_ip": "192.168.1.205", "timestamp": "2023-10-25T10:15:00Z", "csp-report": {"document-uri": "http://internal.corp/dashboard", "blocked-uri": "https://sys-update-c2.xyz/api/register", "violated-directive": "connect-src"}}
{"source_ip": "10.0.0.15", "timestamp": "2023-10-25T10:20:00Z", "csp-report": {"document-uri": "http://internal.corp", "blocked-uri": "https://benign-service.xyz/api", "violated-directive": "connect-src"}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
