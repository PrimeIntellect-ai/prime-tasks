#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/input.csv
id,text_log,sensor_value
1,hello world,10.0
2,data science task,12.0
3,rust is fast and safe,
4,test,8.0
5,one two three four five,14.0
6,a b c,
7,missing values are tricky,16.0
8,outlier here,30.0
9,test set row,
10,another test row,11.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
