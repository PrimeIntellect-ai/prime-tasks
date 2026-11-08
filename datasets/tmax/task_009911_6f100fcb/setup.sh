#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_app.log
[2023-10-24 10:00:05] IP=192.168.1.50 STATUS=200 TIME=100 MSG=OK
[2023-10-24 10:00:25] IP=192.168.1.51 STATUS=200 TIME=150 MSG=OK
[2023-10-24 10:00:55] IP=192.168.1.52 STATUS=200 TIME=120 MSG=Slow DB connection
[2023-10-24 10:01:15] IP=10.0.0.5 STATUS=500 TIME=800 MSG=Exception occurred:
java.lang.NullPointerException
  at com.app.Main(Main.java:25)
  at com.app.Runner(Runner.java:10)
[2023-10-24 10:01:45] IP=10.0.0.6 STATUS=500 TIME=600 MSG=Database timeout
[2023-10-24 10:02:10] IP=192.168.2.10 STATUS=200 TIME=100 MSG=OK
[2023-10-24 10:02:30] IP=192.168.2.11 STATUS=200 TIME=200 MSG=OK
[2023-10-24 10:02:45] IP=192.168.2.12 STATUS=200 TIME=150 MSG=OK
[2023-10-24 10:02:59] IP=192.168.2.13 STATUS=200 TIME=100 MSG=OK
[2023-10-24 10:03:05] IP=172.16.0.2 STATUS=503 TIME=400 MSG=Service Unavailable
[2023-10-24 10:03:35] IP=172.16.0.3 STATUS=503 TIME=600 MSG=Service Unavailable
[2023-10-24 10:03:50] IP=172.16.0.4 STATUS=500 TIME=550 MSG=Connection reset
by peer
[2023-10-24 10:04:10] IP=8.8.8.8 STATUS=200 TIME=50 MSG=OK
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
