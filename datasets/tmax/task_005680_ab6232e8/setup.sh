#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/source_data/level1/level2
    mkdir -p /home/user/backup_dest

    cat << 'EOF' > /home/user/backup_config.json
{
  "source_dir": "/home/user/source_data",
  "dest_dir": "/home/user/backup_dest",
  "encodings": {
    ".csv": "utf-16le",
    ".xml": "iso-8859-1",
    ".json": "utf-8"
  },
  "compression_key": 42
}
EOF

    echo '{"status": "ok", "data": "hello world"}' > /home/user/source_data/info.json

    echo 'id,name,value' | iconv -f UTF-8 -t UTF-16LE > /home/user/source_data/level1/data.csv
    echo '1,test,100' | iconv -f UTF-8 -t UTF-16LE >> /home/user/source_data/level1/data.csv

    echo '<?xml version="1.0"?><root><item>café</item></root>' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/source_data/level1/level2/config.xml

    ln -s /home/user/source_data/level1/level2 /home/user/source_data/level1/valid_link
    ln -s /home/user/source_data /home/user/source_data/level1/level2/loop_link

    chmod -R 777 /home/user
