#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/web_incident/certs

    cat << 'EOF' > /home/user/web_incident/access.log
192.168.1.15 - - [10/Oct/2023:13:55:36 -0700] "GET /server.sh?user=admin HTTP/1.1" 200 18
10.0.5.22 - - [10/Oct/2023:13:56:01 -0700] "GET /server.sh?user=guest HTTP/1.1" 200 18
172.16.0.45 - - [10/Oct/2023:14:05:12 -0700] "GET /server.sh?user=admin%20%3B%20cat%20certs%2Fserver.key HTTP/1.1" 200 1674
192.168.1.10 - - [10/Oct/2023:14:10:05 -0700] "GET /server.sh?user=alice HTTP/1.1" 200 18
EOF

    cat << 'EOF' > /home/user/web_incident/server.sh
#!/bin/bash
USER_INPUT=$1
eval "echo Welcome $USER_INPUT"
EOF

    cat << 'EOF' > /home/user/web_incident/certs/server.key
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQ...
-----END PRIVATE KEY-----
EOF

    chmod -R 777 /home/user

    # Apply specific permissions after the recursive chmod
    chmod +x /home/user/web_incident/server.sh
    chmod 644 /home/user/web_incident/certs/server.key
