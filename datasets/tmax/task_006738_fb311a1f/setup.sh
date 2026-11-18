#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
pip3 install pytest

mkdir -p /home/user/setup_tmp/node_alpha
mkdir -p /home/user/setup_tmp/node_beta

# node_alpha
cat << 'EOF' > /home/user/setup_tmp/node_alpha/v1.gcode
G21 ; metric values
G90 ; absolute positioning
M82 ; set extruder to absolute mode
M92 X80.0 Y80.0 Z400.0 E90.0 ; Set axis steps per unit
EOF

cat << 'EOF' > /home/user/setup_tmp/node_alpha/v2.gcode
G21
G90
M82
M92 X80.0 Y80.0 Z400.0 E92.5 ; Set axis steps per unit
EOF

cat << 'EOF' > /home/user/setup_tmp/node_alpha/v3.gcode
G21
G90
M82
M92 X80.0 Y80.0 Z400.0 E94.0 ; Set axis steps per unit
EOF

# node_beta
cat << 'EOF' > /home/user/setup_tmp/node_beta/v1.gcode
G21
G90
M82
M92 X100.0 Y100.0 Z400.0 E100.0 ; Set axis steps per unit
EOF

cat << 'EOF' > /home/user/setup_tmp/node_beta/v2.gcode
G21
G90
M82
M92 X100.0 Y100.0 Z400.0 E98.5 ; Set axis steps per unit
EOF

cat << 'EOF' > /home/user/setup_tmp/node_beta/v3.gcode
G21
G90
M82
M92 X100.0 Y100.0 Z400.0 E99.0 ; Set axis steps per unit
EOF

cd /home/user/setup_tmp/node_alpha && zip -r ../node_alpha.zip ./*
cd /home/user/setup_tmp/node_beta && zip -r ../node_beta.zip ./*
cd /home/user/setup_tmp && tar -czvf /home/user/cnc_configs.tar.gz node_alpha.zip node_beta.zip

rm -rf /home/user/setup_tmp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
