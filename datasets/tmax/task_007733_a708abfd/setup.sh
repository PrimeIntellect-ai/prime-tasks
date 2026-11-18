#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
Sensor_ID,Temp,Pressure,Humidity,Vibration
S1,10.0,100.0,50.0,10.0
S2,15.5,80.0,40.0,5.0
S3,20.0,bad,50.0,10.0
S4,100.0,150.0,20.0,20.0,extra
S5,0.0,200.0,10.0,30.0
S6,-10.0,120.0,60.0,5.0
S7,-5.0,90.0,50.0,0.0
S8,5.0,100.0,-20.0,10.0
S9,10,100,50,10
EOF

    chmod -R 777 /home/user
