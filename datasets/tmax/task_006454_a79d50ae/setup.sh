#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd curl lsof
    pip3 install pytest

    mkdir -p /home/user

    # Create the user accounts file
    cat << 'EOF' > /home/user/container_users.txt
root:x:0:0:root:/root:/bin/bash
py-service:x:1001:1001:Python Microservice:/app/py:/bin/false
node-service:x:1002:1002:Node Microservice:/app/node:/bin/false
go-service:x:1003:1003:Go Microservice:/app/go:/bin/false
EOF

    # Create the filesystem metadata dump
    cat << 'EOF' > /home/user/fs_meta.txt
py-service 1001
node-service 1099
go-service 1003
EOF

    # Create a script to start the dummy services when the container runs
    cat << 'EOF' > /.singularity.d/env/99-services.sh
#!/bin/bash
# Start dummy background listeners for ports 8001 and 8003 if not already running
python3 -c "import http.server; import socketserver; socketserver.TCPServer(('', 8001), http.server.SimpleHTTPRequestHandler).serve_forever()" >/dev/null 2>&1 &
python3 -c "import http.server; import socketserver; socketserver.TCPServer(('', 8003), http.server.SimpleHTTPRequestHandler).serve_forever()" >/dev/null 2>&1 &
sleep 0.5
EOF
    chmod +x /.singularity.d/env/99-services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
