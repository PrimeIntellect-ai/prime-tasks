#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl zip unzip fcrackzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the log file
    cat << 'EOF' > /home/user/c2_traffic.log
2023-10-25 08:12:01 [INFO] Connection established from 192.168.1.50
2023-10-25 08:12:05 [DEBUG] TX: SGVsbG8gQzI=
2023-10-25 08:12:06 [DEBUG] RX: U3RhdHVzIE9L
2023-10-25 08:15:22 [DEBUG] RX: VG8gZXh0cmFjdCB0aGUgZXZpZGVuY2UuemlwLCB1c2UgYSA0LWRpZ2l0IFBJTi4=
2023-10-25 08:16:00 [INFO] Connection closed
EOF

    # Generate the certificate
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/server.key -out /tmp/server.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=evil.corp.local"

    # Create the encrypted zip file
    cd /tmp
    zip --password 8319 /home/user/evidence.zip server.crt

    # Clean up
    rm /tmp/server.crt /tmp/server.key

    # Set permissions
    chmod -R 777 /home/user
