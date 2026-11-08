#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq libxml2-utils gawk tar grep
    pip3 install pytest

    mkdir -p /home/user/setup_temp/dir1/dir2
    mkdir -p /home/user/setup_temp/dir3

    cat << 'EOF' > /home/user/setup_temp/dir1/meta1.json
{
  "project_name": "Apollo Lunar",
  "version": "1.0"
}
EOF

    cat << 'EOF' > /home/user/setup_temp/dir1/dir2/meta2.xml
<?xml version="1.0" encoding="UTF-8"?>
<root>
    <project_name>Gemini</project_name>
    <author>John Doe</author>
</root>
EOF

    cat << 'EOF' > /home/user/setup_temp/dir3/data.csv
project_name,version,date
Artemis Base,3.0,2023-01-01
EOF

    cat << 'EOF' > /home/user/setup_temp/dir3/meta3.json
{
  "project_name": "Gemini",
  "status": "active"
}
EOF

    cd /home/user/setup_temp && tar -czf /home/user/data.tar.gz *
    rm -rf /home/user/setup_temp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
