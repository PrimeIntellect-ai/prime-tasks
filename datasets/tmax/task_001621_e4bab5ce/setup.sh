#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence
    cat << 'EOF' > /home/user/evidence/network_log.txt
192.168.1.50 10.0.0.1 22 AUTH_SUCCESS user_login
192.168.1.100 10.0.0.1 8080 AUTH_FAILED invalid
10.0.0.5 10.0.0.1 80 SYSTEM_PING ok
192.168.1.100 10.0.0.1 8080 AUTH_SUCCESS T0k3nM4st3r
192.168.1.50 10.0.0.1 22 CMD_EXEC ls_-la
192.168.1.100 10.0.0.1 8080 EXFIL 177f25752709713d207a3318
192.168.1.100 10.0.0.1 8080 CMD_EXEC tar_czf_data
192.168.1.100 10.0.0.1 8080 EXFIL 6f24632b1f75273d7c3c0b64
10.0.0.5 10.0.0.1 80 SYSTEM_PING ok
192.168.1.100 10.0.0.1 8080 EXFIL 39762f0967273b7d370b7128
192.168.1.100 10.0.0.1 8080 EXFIL 67271b71
EOF

    chown -R user:user /home/user/evidence
    chmod -R 777 /home/user
