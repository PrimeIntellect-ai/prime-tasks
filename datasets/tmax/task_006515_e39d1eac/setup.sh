#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip unzip jq gawk tar coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/raw_drop
cd /home/user/raw_drop

# 1. Valid tar.gz
echo "appx86 payload" > app_payload.txt
tar -czf app-x86_64-v1.tar.gz app_payload.txt
HASH1=$(sha256sum app-x86_64-v1.tar.gz | awk '{print $1}')

# 2. Valid zip
echo "apparm payload" > app_payload2.txt
zip -q app-arm64-v1.zip app_payload2.txt
HASH2=$(sha256sum app-arm64-v1.zip | awk '{print $1}')

# 3. Corrupt archive (fails integrity)
echo "This is not a valid tarball" > lib-x86_64-v2.tar.gz
HASH3=$(sha256sum lib-x86_64-v2.tar.gz | awk '{print $1}')

# 4. Bit-rot archive (checksum mismatch)
echo "tools payload" > tools_payload.txt
tar -czf tools-arm64-v3.tar.gz tools_payload.txt
HASH4=$(sha256sum tools-arm64-v3.tar.gz | awk '{print $1}')
FAKE_HASH="1111111111111111111111111111111111111111111111111111111111111111"

# Generate vendor_manifest.json
cat <<EOF > vendor_manifest.json
[
  {"file": "app-x86_64-v1.tar.gz", "project": "app", "arch": "x86_64"},
  {"file": "app-arm64-v1.zip", "project": "app", "arch": "arm64"},
  {"file": "lib-x86_64-v2.tar.gz", "project": "lib", "arch": "x86_64"},
  {"file": "tools-arm64-v3.tar.gz", "project": "tools", "arch": "arm64"}
]
EOF

# Generate ingest.log
cat <<EOF > ingest.log
[START]
Timestamp: 2023-10-01T12:00:00Z
File: app-x86_64-v1.tar.gz
Status: SUCCESS
SHA256: ${HASH1}
[END]
[START]
Timestamp: 2023-10-01T12:01:00Z
File: app-arm64-v1.zip
Status: SUCCESS
SHA256: ${HASH2}
[END]
[START]
Timestamp: 2023-10-01T12:02:00Z
File: lib-x86_64-v2.tar.gz
Status: SUCCESS
SHA256: ${HASH3}
[END]
[START]
Timestamp: 2023-10-01T12:03:00Z
File: tools-arm64-v3.tar.gz
Status: SUCCESS
SHA256: ${FAKE_HASH}
[END]
EOF

rm app_payload.txt app_payload2.txt tools_payload.txt

chmod -R 777 /home/user
