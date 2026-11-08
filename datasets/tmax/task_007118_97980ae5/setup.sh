#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/metadata.csv
ID,Age,Group
SUB001,25,Control
SUB002,17,Test
SUB003,45,Control
SUB004,abc,Test
SUB005,30,Test
EOF

    cat << 'EOF' > /home/user/data/sensors.json
[
  {"ID": "SUB001", "Sensor_A": 1.2, "Sensor_B": 0.5},
  {"ID": "SUB002", "Sensor_A": 0.9, "Sensor_B": 0.1},
  {"ID": "SUB003", "Sensor_A": -0.5, "Sensor_B": 1.1},
  {"ID": "SUB004", "Sensor_A": 1.0, "Sensor_B": 1.0},
  {"ID": "SUB005", "Sensor_A": 0.0, "Sensor_B": -0.2}
]
EOF

    cat << 'EOF' > /home/user/data/model_config.json
{
  "weights": {
    "Age": 0.05,
    "Sensor_A": -1.2,
    "Sensor_B": 0.8
  },
  "bias": -0.5,
  "activation": "sigmoid"
}
EOF

    chmod -R 777 /home/user
