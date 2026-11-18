#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssl systemd dbus
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/logs
    mkdir -p /home/user/.config/systemd/user/

    cat << 'EOF' > /home/user/app/run.sh
#!/bin/bash
# Initialize logs
echo "Initializing secure web app..." > /home/user/app/logs/startup.log
# Attempt to write a larger log file (which will fail if LimitFSIZE is too low)
head -c 5000 /dev/urandom | base64 >> /home/user/app/logs/startup.log

cd /home/user/app

# Start a simple HTTPS server
python3 -c "
import http.server, ssl
server_address = ('127.0.0.1', 8443)
httpd = http.server.HTTPServer(server_address, http.server.SimpleHTTPRequestHandler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(certfile='cert.pem', keyfile='key.pem')
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
"
EOF

    chmod +x /home/user/app/run.sh

    cat << 'EOF' > /home/user/.config/systemd/user/secure-app.service
[Unit]
Description=Secure Web App

[Service]
ExecStart=/home/user/app/run.sh
WorkingDirectory=/home/user/app
LimitFSIZE=1
Restart=no

[Install]
WantedBy=default.target
EOF

    chown -R user:user /home/user/app
    chown -R user:user /home/user/.config

    chmod -R 777 /home/user
