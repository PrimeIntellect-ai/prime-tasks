#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import csv

data = [
    [1, "2023-10-01T08:00:00", "Café_Étoile", 10.0],
    [2, "2023-10-01T09:00:00", "Café_Étoile", None],
    [3, "2023-10-01T10:00:00", "Café_Étoile", 20.0],
    [4, "2023-10-01T11:00:00", "Entrée_Principale", 22.0],
    [5, "2023-10-01T12:00:00", "Café_Étoile", None],
    [6, "2023-10-01T13:00:00", "Café_Étoile", 25.0],
    [7, "2023-10-01T14:00:00", "Café_Étoile", 26.0],
    [8, "2023-10-01T15:00:00", "Café_Étoile", None],
    [9, "2023-10-01T16:00:00", "Café_Étoile", 30.0],
]

with open('/home/user/raw_sensors.csv', 'wb') as f:
    for row in data:
        line = f"{row[0]},{row[1]},{row[2]},{row[3] if row[3] is not None else ''}\n"
        f.write(line.encode('iso-8859-1'))
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
