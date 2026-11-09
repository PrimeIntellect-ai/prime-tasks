#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/cgi-bin

    cat << 'EOF' > /home/user/known_malware_hashes.txt
22ea0d2a5cf3ba5bb619ca2ee62df00e5ba6445582c0697d264f331cf1ea80f6
0000000000000000000000000000000000000000000000000000000000000000
EOF

    cat << 'EOF' > /home/user/traffic_log.txt
===RESPONSE_ID: 101===
[Headers]
Content-Type: text/html
Content-Security-Policy: default-src 'self'
Connection: keep-alive
[Body_Base64]
ZWNobyAnc2FmZSc=
===END===
===RESPONSE_ID: 102===
[Headers]
Content-Type: text/html
Content-Security-Policy: default-src 'self'; script-src 'unsafe-inline'
X-Powered-By: Bash
[Body_Base64]
Y3VybCBodHRwOi8vZXZpbC5jb20vbWFsd2FyZS5zaCB8IHNo
===END===
===RESPONSE_ID: 103===
[Headers]
Content-Type: text/html
Server: Apache
[Body_Base64]
PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==
===END===
EOF

    cat << 'EOF' > /home/user/cgi-bin/ping.cgi
#!/bin/bash
echo "Content-type: text/plain"
echo ""
target=$(echo "$QUERY_STRING" | grep -oE "target=[^&]+" | cut -d= -f2)
ping -c 1 $target
EOF

    cat << 'EOF' > /home/user/cgi-bin/greet.cgi
#!/bin/bash
echo "Content-type: text/html"
echo ""
name=$(echo "$QUERY_STRING" | grep -oE "name=[^&]+" | cut -d= -f2)
echo "<html><body><h1>Hello $name</h1></body></html>"
EOF

    cat << 'EOF' > /home/user/cgi-bin/download.cgi
#!/bin/bash
echo "Content-type: application/octet-stream"
echo ""
file=$(echo "$QUERY_STRING" | grep -oE "file=[^&]+" | cut -d= -f2)
cat /var/www/uploads/$file
EOF

    chmod +x /home/user/cgi-bin/ping.cgi
    chmod +x /home/user/cgi-bin/greet.cgi
    chmod +x /home/user/cgi-bin/download.cgi

    chmod -R 777 /home/user
