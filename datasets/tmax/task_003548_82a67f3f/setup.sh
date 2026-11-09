#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl tar jq file
    pip3 install pytest pyyaml

    mkdir -p /app/shyaml-0.6.2

    cat << 'EOF' > /app/shyaml-0.6.2/setup.py
from setuptools import setup
setup(
    name='shyaml',
    version='0.6.2',
    scripts=['shyaml'],
    install_requires=['PyYAML>=3.10
)
EOF

    cat << 'EOF' > /app/shyaml-0.6.2/shyaml
#!/usr/bin/env python3
import sys
import yaml

def main():
    data = yaml.safe_load(sys.stdin)
    if len(sys.argv) >= 3 and sys.argv[1] == 'get-value':
        key = sys.argv[2]
        value = data.get(key, "")
        print_value(str(value))

if __name__ == '__main__':
    main()

# 16
# 17
# 18
# 19
# 20
# 21
# 22
# 23
# 24
# 25
# 26
# 27
# 28
# 29
# 30
# 31
# 32
# 33
# 34
# 35
# 36
# 37
# 38
# 39
# 40
def print_value(value):
    sys.stdout.write(value
EOF

    chmod +x /app/shyaml-0.6.2/shyaml

    mkdir -p /app/legacy_repo
    mkdir -p /truth

    cat << 'EOF' > /app/repo_config.ini
[rename]
old_art1.tar.gz = new_art1.tar.gz
old_art2.tar.gz = new_art2.tar.gz
EOF

    for i in 1 2; do
        mkdir -p /tmp/art$i
        echo "dummy binary payload $i" > /tmp/art$i/payload.bin
        echo "name: artifact$i" > /tmp/art$i/metadata.txt
        echo "status: __STATUS__" >> /tmp/art$i/metadata.txt
        echo "author: admin" >> /tmp/art$i/metadata.txt
        # Convert to ISO-8859-1
        iconv -f UTF-8 -t ISO-8859-1 /tmp/art$i/metadata.txt -o /tmp/art$i/metadata_iso.txt
        mv /tmp/art$i/metadata_iso.txt /tmp/art$i/metadata.txt
        tar -czf /app/legacy_repo/old_art$i.tar.gz -C /tmp/art$i payload.bin metadata.txt
    done

    cat << 'EOF' > /truth/expected_manifest.json
[
  {
    "artifact_name": "new_art1.tar.gz",
    "metadata": {
      "name": "artifact1",
      "status": "CURATED",
      "author": "admin"
    }
  },
  {
    "artifact_name": "new_art2.tar.gz",
    "metadata": {
      "name": "artifact2",
      "status": "CURATED",
      "author": "admin"
    }
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /truth
