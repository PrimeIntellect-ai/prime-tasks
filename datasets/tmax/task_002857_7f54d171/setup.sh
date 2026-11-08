#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
with open("/home/user/raw_sensor_data.csv", "wb") as f:
    f.write(b"""timestamp_ms,sensor_id,temperature,humidity,status_message
1000,S1,20.5,45.0,OK
1000,S1,21.0,46.0,DUPE_SHOULD_DROP
1005,S1,160.0,45.0,INVALID_TEMP
1010,S1,22.0,47.0,Warn\xEDng
1015,S1,21.5,50.0,OK
1020,S1,23.0,105.0,INVALID_HUM
1025,S2,10.0,30.0,OK
1030,S1,24.0,55.0,OK
1035,S2,11.0,31.0,OK
""")
'

    chmod -R 777 /home/user
