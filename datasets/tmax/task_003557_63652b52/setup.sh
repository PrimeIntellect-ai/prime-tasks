#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang ffmpeg build-essential wget espeak curl
pip3 install pytest

mkdir -p /home/user/data
mkdir -p /app

cat << 'EOF' > /home/user/data/historical_records.csv
Customer Name,Account ID,Reported Issue
Alice Smith,ACC-11111,Network down
Alice Smit,ACC-11111,Networ down
Bob Jones,ACC-22222,Login failed
Bob Jone,ACC-22222,Login fail
Jonatan Harker,ACC-99281,Vampir bats in server rom
EOF

espeak -w /app/call_recording.wav "This is Jonathan Harker, my account ID is ACC hyphen nine nine two eight one. The reported issue is vampire bats in the server room."

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
