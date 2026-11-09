#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_telemetry.txt
1680000015;SENS_88;24.0;All gõod
1680000020;SENS_99;100.0;Ignore this completely
1680000010;SENS_88;22.5;Normal
1680000005;SENS_88;21.0;Wärming üp
1680000030;SENS_88;20.5;Ståble
1680000025;SENS_88;25.5;Hõt!
1680000035;SENS_88;19.0;Coolìng
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
