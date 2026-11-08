#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/weather_logs.csv
hour,text
0,Clear skies!
1,Clear skies, light wind.
4,Cloudy, 50% chance of rain.
5,Heavy Rain!!!
20,Clear and calm.
23,Clear.
EOF

    chmod -R 777 /home/user
