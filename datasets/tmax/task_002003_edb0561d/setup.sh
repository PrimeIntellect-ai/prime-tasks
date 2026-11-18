#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat curl sed
    pip3 install pytest

    mkdir -p /home/user/src/cgi-bin

    cat << 'EOF' > /home/user/src/cgi-bin/greet.sh
#!/bin/bash
echo "Content-Type: text/html"
echo ""
echo "<html><body>"
# INSECURE COMMAND INJECTION VULNERABILITY
NAME=$(echo $QUERY_STRING | sed -n 's/^.*name=\([^&]*\).*$/\1/p')
eval "echo Hello, $NAME"
echo "</body></html>"
EOF
    chmod +x /home/user/src/cgi-bin/greet.sh

    cat << 'EOF' > /home/user/server_setup.sh
#!/bin/bash
mkdir -p /home/user/www/config
mkdir -p /home/user/www/cgi-bin
cp /home/user/src/cgi-bin/greet.sh /home/user/www/cgi-bin/greet.sh

# INSECURE FILE PERMISSIONS
echo "super_secret_db_password_123" > /home/user/www/config/db_secret.key
# Missing chmod 600 here

# Start server
# INSECURE HTTP HEADERS
socat TCP-LISTEN:8080,reuseaddr,fork SYSTEM:"echo HTTP/1.1 200 OK; echo Content-Type\: text/html; echo; /home/user/www/cgi-bin/greet.sh"
EOF
    chmod +x /home/user/server_setup.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
