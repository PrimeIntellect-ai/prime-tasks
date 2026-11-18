#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gzip coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs/

cat << 'EOF' > /tmp/log1.txt
===ARTIFACT===
File: kernel_module_x86.tar.gz
Uploader: Jenkins
Status: VERIFIED
Timestamp: 1699999900
===END===
===ARTIFACT===
File: broken_lib.so
Uploader: Jenkins
Status: CORRUPT
Timestamp: 1699999905
===END===
===ARTIFACT===
File: auth_service_v2.tar.gz
Uploader: GitLabCI
Status: VERIFIED
Timestamp: 1699999910
===END===
EOF

cat << 'EOF' > /tmp/log2.txt
===ARTIFACT===
File: data_pipeline.tar.gz
Uploader: Cron
Status: UPLOADING
Timestamp: 1699999920
===END===
===ARTIFACT===
File: ui_assets.zip
Uploader: GitHubActions
Status: VERIFIED
Timestamp: 1699999930
===END===
EOF

gzip -c /tmp/log1.txt | base64 > /home/user/logs/batch_A.b64z
gzip -c /tmp/log2.txt | base64 > /home/user/logs/batch_B.b64z

rm /tmp/log1.txt /tmp/log2.txt
chown -R user:user /home/user/logs

chmod -R 777 /home/user
