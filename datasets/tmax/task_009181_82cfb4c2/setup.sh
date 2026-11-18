#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.log
[2023/10/01] Unit-Alpha reported Temp: 104F and Pressure: 14.5psi. Routine check.
[10-02-2023] Unit-Beta temp is 40C, press is 100kPa.
[2023/10/03] Unit-Gamma Temp: 95.5F, Pressure: 15.2psi.
System restart initiated by admin.
[10-04-2023] Unit-Delta Temp: 22C, press: 101.3kPa.
[2023/10/05] Error reading sensor.
[12-31-2022] Unit-Epsilon reported 32F and 14.7psi.
Unit-Zeta [2023/01/01] Temp: 0C Pressure: 0kPa
EOF

    chmod -R 777 /home/user
