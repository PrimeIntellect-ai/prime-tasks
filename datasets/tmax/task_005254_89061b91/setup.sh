#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip grep gawk sed coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/server.log
[2023-10-01 10:00:01] INFO 200 - Client: 192.168.1.1 - Success
{"timestamp": "2023-10-01T10:00:02Z", "level": "ERROR", "status_code": 502, "client_ip": "10.0.0.99"}
[2023-10-01 10:00:03] ERROR 502 - Client: 192.168.1.50 - Request failed
[2023-10-01 10:00:04] ERROR 502 - Client: 192.168.1.50 - Request failed
{"timestamp": "2023-10-01T10:00:05Z", "level": "INFO", "status_code": 200, "client_ip": "10.0.0.99"}
{"timestamp": "2023-10-01T10:00:06Z", "level": "ERROR", "status_code": 502, "client_ip": "10.0.0.99"}
[2023-10-01 10:00:07] ERROR 502 - Client: 192.168.1.50 - Request failed
{"timestamp": "2023-10-01T10:00:08Z", "level": "ERROR", "status_code": 502, "client_ip": "172.16.5.18"}
[2023-10-01 10:00:09] ERROR 404 - Client: 192.168.1.50 - Not found
{"timestamp": "2023-10-01T10:00:10Z", "level": "ERROR", "status_code": 502, "client_ip": "10.0.0.99"}
[2023-10-01 10:00:11] ERROR 502 - Client: 172.16.5.18 - Request failed
{"timestamp": "2023-10-01T10:00:12Z", "level": "ERROR", "status_code": 502, "client_ip": "192.168.1.50"}
[2023-10-01 10:00:13] ERROR 502 - Client: 192.168.1.50 - Request failed
{"timestamp": "2023-10-01T10:00:14Z", "level": "ERROR", "status_code": 502, "client_ip": "10.0.0.99"}
[2023-10-01 10:00:15] ERROR 502 - Client: 10.0.0.99 - Request failed
{"timestamp": "2023-10-01T10:00:16Z", "level": "ERROR", "status_code": 502, "client_ip": "192.168.1.50"}
[2023-10-01 10:00:17] ERROR 502 - Client: 172.16.5.18 - Request failed
{"timestamp": "2023-10-01T10:00:18Z", "level": "ERROR", "status_code": 502, "client_ip": "192.168.1.50"}
[2023-10-01 10:00:19] ERROR 502 - Client: 192.168.1.50 - Request failed
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
