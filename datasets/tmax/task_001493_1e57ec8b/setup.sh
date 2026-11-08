#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/logs /home/user/certs /home/user/scripts

    cat << 'EOF' > /home/user/logs/process_exec.log
[2023-10-25 10:00:00] EXEC: /usr/bin/python3 app.py --config /etc/app.conf
[2023-10-25 10:05:12] EXEC: /usr/bin/python3 app.py --config /etc/app.conf --pin-hash 81dc9bdb52d04dc20036dbd8313ed055
[2023-10-25 10:10:00] EXEC: /usr/bin/python3 worker.py --threads 4
EOF

    openssl genrsa -aes256 -passout pass:1234 -out /home/user/certs/encrypted_app.key 2048

    cat << 'EOF' > /home/user/scripts/deploy_db.sh
#!/bin/bash
echo "Deploying DB"
/usr/bin/mysql_client --host db.local --password=supersecretDB1! --user root
EOF

    cat << 'EOF' > /home/user/scripts/start_api.sh
#!/bin/bash
# Start the API
./api_server -p P@ssw0rd2023 --port 8080
EOF

    cat << 'EOF' > /home/user/scripts/safe_script.sh
#!/bin/bash
# This script is safe
echo "Hello World"
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
