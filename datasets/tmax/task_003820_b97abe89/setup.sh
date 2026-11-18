#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl wget g++ espeak ffmpeg
pip3 install --default-timeout=100 pytest SpeechRecognition

mkdir -p /app
espeak -w /app/alert.wav "Critical failure. Commence audit on backup node delta niner four."

mkdir -p /home/user
wget -qO /home/user/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h
wget -qO /home/user/json.hpp https://raw.githubusercontent.com/nlohmann/json/develop/single_include/nlohmann/json.hpp

cat << 'EOF' > /home/user/backups.json
[
  {"id": "A-01", "parent_id": null, "timestamp": 1600000000, "status": "SUCCESS"},
  {"id": "D-94", "parent_id": "A-01", "timestamp": 1600001000, "status": "SUCCESS"},
  {"id": "D-95", "parent_id": "D-94", "timestamp": 1600002000, "status": "SUCCESS"},
  {"id": "D-96", "parent_id": "D-94", "timestamp": 1600003000, "status": "FAILED"},
  {"id": "D-97", "parent_id": "D-95", "timestamp": 1600004000, "status": "SUCCESS"},
  {"id": "D-98", "parent_id": "D-97", "timestamp": 1600005000, "status": "SUCCESS"},
  {"id": "X-10", "parent_id": "A-01", "timestamp": 1600001500, "status": "SUCCESS"}
]
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
chmod -R 777 /app
