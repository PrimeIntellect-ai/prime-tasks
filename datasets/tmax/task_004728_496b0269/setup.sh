#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make nlohmann-json3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.txt
System boot.
Signal lost at coords: [1.012, 2.015, 3.010]. Rebooting...
Interference detected near [1.049, 2.022, 3.041]. Ignoring.
Valid reading found! [4.011, 5.011, 6.011]. Storing to database.
Error: out of bounds at [-999.9, abc, 123]
Secondary sensor triggered: [7.019, 8.019, 9.019]
Duplicate log for [1.010, 2.010, 3.010] received.
EOF

    chmod -R 777 /home/user
