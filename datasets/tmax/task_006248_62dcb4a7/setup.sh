#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mocks

    cat << 'EOF' > /home/user/service_mounts.txt
# Current system states
cont-web    CONTAINER  RUNNING   PORT=8080      /home/user/mocks/run_web.sh
cont-db     CONTAINER  FAILED    DB_USER=root   /home/user/mocks/run_db.sh
disk-1      MOUNT      FAILED    MOUNT=/data    /bin/false
cont-api    CONTAINER  FAILED    API_ENV=prod   /home/user/mocks/run_api.sh
cont-cache  CONTAINER  FAILED    CACHE_SIZE=10  /home/user/mocks/run_cache.sh
EOF

    cat << 'EOF' > /home/user/mocks/run_web.sh
#!/bin/bash
exit 0
EOF

    cat << 'EOF' > /home/user/mocks/run_db.sh
#!/bin/bash
if [ "$DB_USER" != "root" ]; then exit 2; fi
if [ ! -f /tmp/db_run ]; then touch /tmp/db_run; exit 1; else exit 0; fi
EOF

    cat << 'EOF' > /home/user/mocks/run_api.sh
#!/bin/bash
if [ "$API_ENV" != "prod" ]; then exit 2; fi
if [ ! -f /tmp/api_run ]; then touch /tmp/api_run; exit 1; else exit 0; fi
EOF

    cat << 'EOF' > /home/user/mocks/run_cache.sh
#!/bin/bash
if [ "$CACHE_SIZE" != "10" ]; then exit 2; fi
exit 1
EOF

    chmod +x /home/user/mocks/*.sh

    chmod -R 777 /home/user
