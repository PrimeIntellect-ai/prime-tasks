#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/remote_share

    # Create Gamma (UTF-8, YYYY-MM-DD HH:MM:SS)
    cat << 'EOF' > /home/user/remote_share/server_gamma.log
2023-10-11 12:10:00 [CRITICAL] 192.168.1.10 - Code 403: Forbidden
2023-10-11 12:12:00 [INFO] 10.0.0.1 - Code 200: OK
2023-10-11 14:00:00 [ERROR] 10.1.2.3 - Code 500: Internal Server Error
EOF

    # Create Beta (ISO-8859-1, MM/DD/YYYY HH:MM:SS)
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/remote_share/server_beta.log
10/11/2023 12:05:00 [ERROR] 172.16.0.4 - Code 404: Not Found
10/12/2023 08:30:00 [WARNING] 172.16.0.5 - Code 429: Too Many Requests
10/13/2023 09:15:00 [CRITICAL] 172.16.1.99 - Code 503: Service Unavailable
EOF

    # Create Alpha (UTF-16LE, Epoch)
    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > /home/user/remote_share/server_alpha.log
1697025600 [CRITICAL] 192.168.1.10 - Code 502: Bad Gateway
1697025650 [INFO] 10.0.0.5 - Code 200: OK
1697030000 [ERROR] 192.168.2.50 - Code 401: Unauthorized
EOF

    chown -R user:user /home/user/remote_share
    chmod -R 777 /home/user
