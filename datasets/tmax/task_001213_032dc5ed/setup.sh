#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil
    mkdir -p /home/user/app

    for i in $(seq 1 10); do
        echo "clean data $i" > /home/user/corpus/clean/file$i.txt
    done

    for i in $(seq 1 10); do
        echo "evil data <script> $i" > /home/user/corpus/evil/file$i.txt
    done

    cat << 'EOF' > /home/user/app/api_gateway.py
#!/usr/bin/env python3
print("API Gateway")
EOF

    cat << 'EOF' > /home/user/app/app_backend.py
#!/usr/bin/env python3
print("App Backend")
EOF

    cat << 'EOF' > /home/user/app/db_service.py
#!/usr/bin/env python3
print("DB Service")
EOF

    cat << 'EOF' > /home/user/app/db_init_cli.py
#!/usr/bin/env python3
print("DB Init CLI")
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
echo "Starting services"
EOF

    chmod +x /home/user/app/*.py /home/user/app/*.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
