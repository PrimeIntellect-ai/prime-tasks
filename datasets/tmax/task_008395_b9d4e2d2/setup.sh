#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/fetch_document.sh
#!/bin/bash
echo "Content-type: text/plain"
echo ""

# Extract doc parameter
DOC_PARAM=$(echo "$QUERY_STRING" | grep -oP '(?<=doc=)[^&]*')

# Vulnerable file read
if [ -n "$DOC_PARAM" ]; then
    cat "/var/www/documents/$DOC_PARAM"
else
    echo "No document specified."
fi
EOF

    cat << 'EOF' > /home/user/auth.log
[2023-11-01 08:12:05] Event: LOGIN | User: alice | Token: sess_8f2a1b
[2023-11-01 09:30:11] Event: LOGIN | User: bob_admin | Token: sess_99xbc2
[2023-11-01 10:14:22] Event: LOGIN | User: charlie | Token: sess_xyz123
[2023-11-01 11:05:00] Event: LOGIN | User: malicious_dave | Token: sess_evil666
EOF

    cat << 'EOF' > /home/user/access.log
192.168.1.50 - - [01/Nov/2023:08:15:00 +0000] "GET /cgi-bin/fetch_document.sh?doc=annual_report.pdf HTTP/1.1" 200 1024 "-" "Session=sess_8f2a1b"
10.0.5.12 - - [01/Nov/2023:09:45:12 +0000] "GET /cgi-bin/fetch_document.sh?doc=policy.txt HTTP/1.1" 200 512 "-" "Session=sess_99xbc2"
172.16.0.4 - - [01/Nov/2023:10:20:05 +0000] "GET /cgi-bin/fetch_document.sh?doc=../../../etc/passwd HTTP/1.1" 200 2048 "-" "Session=sess_xyz123"
192.168.1.50 - - [01/Nov/2023:10:25:00 +0000] "GET /cgi-bin/fetch_document.sh?doc=summary.pdf HTTP/1.1" 200 1024 "-" "Session=sess_8f2a1b"
203.0.113.88 - - [01/Nov/2023:11:10:33 +0000] "GET /cgi-bin/fetch_document.sh?doc=..%2F..%2F..%2Fetc%2Fshadow HTTP/1.1" 200 1024 "-" "Session=sess_evil666"
EOF

    chmod -R 777 /home/user
