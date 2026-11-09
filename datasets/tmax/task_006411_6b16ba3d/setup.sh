#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/repo

    cat << 'EOF' > /home/user/drop_artifacts.sh
#!/bin/bash

# Create valid artifact 1
mkdir -p /tmp/v1
echo '{"category": "database", "name": "sqldb", "version": "1.0.0"}' > /tmp/v1/meta.json
echo "dummy binary data 101010" > /tmp/v1/data.bin
tar -czf /home/user/incoming/db_v1.tar.gz -C /tmp/v1 meta.json data.bin

sleep 1

# Create corrupted artifact
echo "This is not a valid gzip tarball. It is corrupted." > /home/user/incoming/bad_data.tar.gz

sleep 1

# Create valid artifact 2
mkdir -p /tmp/v2
echo '{"category": "web", "name": "server", "version": "2.1.4"}' > /tmp/v2/meta.json
echo "more dummy data" > /tmp/v2/static.css
tar -czf /home/user/incoming/web_v2.tar.gz -C /tmp/v2 meta.json static.css

EOF

    chmod +x /home/user/drop_artifacts.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
