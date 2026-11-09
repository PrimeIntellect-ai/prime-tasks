#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/feedback.csv
id,region,feedback
1,US,This is a test
2,US,Found a massive \u0062\u0075\u0067 in the UI
3,EU,Syst\u00e8me \u0066\u0061\u0069\u006c\u0065\u0064 completely
4,JP,\u30a8\u30e9\u30fc error \u26a0
5,JP,Working normally
6,US,Another BUG encountered here
7,EU,No issues found
8,EU,Minor error on login screen
9,US,The system failed to load \u263a
10,JP,Data \u0062\u0075\u0067 detected
11,EU,Unexpected failure
EOF

    chmod -R 777 /home/user
