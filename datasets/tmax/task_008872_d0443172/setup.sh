#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/wordlist.txt
apple
password
qwerty
hunter2
admin123
letmein
EOF

    cat << 'EOF' > /home/user/app/passwd.db
user:5f4dcc3b5aa765d61d8327deb882cf99
admin:2ab96390c7dbe3439de74d0c9b0b1767
EOF

    cat << 'EOF' > /home/user/app/login.cgi
#!/bin/bash
echo "Content-Type: text/html"

USER=$(echo "$QUERY_STRING" | grep -oP '(?:^|&)user=\K[^&]*')
PASS=$(echo "$QUERY_STRING" | grep -oP '(?:^|&)pass=\K[^&]*')
REDIRECT=$(echo "$QUERY_STRING" | grep -oP '(?:^|&)redirect=\K[^&]*')

HASH=$(echo -n "$PASS" | md5sum | awk '{print $1}')
EXPECTED=$(grep "^$USER:" /home/user/app/passwd.db | cut -d: -f2)

if [ "$HASH" == "$EXPECTED" ] && [ -n "$HASH" ]; then
    if [ -z "$REDIRECT" ]; then REDIRECT="/dashboard"; fi
    echo "Status: 302 Found"
    echo "Location: $REDIRECT"
    echo ""
    echo "Success"
else
    echo "Status: 401 Unauthorized"
    echo ""
    echo "Fail"
fi
EOF
    chmod +x /home/user/app/login.cgi

    cat << 'EOF' > /home/user/ssh_config
Port 22
ListenAddress 0.0.0.0
PermitRootLogin yes
MaxAuthTries 6
PasswordAuthentication yes
X11Forwarding no
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
