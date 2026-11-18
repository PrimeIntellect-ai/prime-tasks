#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/api_dump.json
{
  "packages": {
    "A": [{"version": "1.1", "cost": 5.0}, {"version": "1.2", "cost": 2.0}],
    "B": [{"version": "1.0", "cost": 8.0}, {"version": "2.0", "cost": 3.0}],
    "C": [{"version": "1.5", "cost": 1.0}, {"version": "1.6", "cost": 4.0}, {"version": "2.0", "cost": 10.0}],
    "D": [{"version": "1.0", "cost": 1.0}, {"version": "1.1", "cost": 2.0}]
  },
  "dependencies": {
    "A@1.2": [
      {"package": "B", "min_version": "1.0", "max_version": "2.0"},
      {"package": "C", "min_version": "1.0", "max_version": "1.5"}
    ],
    "A@1.1": [
      {"package": "B", "min_version": "1.0", "max_version": "1.0"},
      {"package": "C", "min_version": "1.5", "max_version": "2.0"}
    ],
    "B@1.0": [
      {"package": "D", "min_version": "1.0", "max_version": "1.0"}
    ],
    "B@2.0": [
      {"package": "D", "min_version": "1.1", "max_version": "1.1"}
    ],
    "C@1.5": [
      {"package": "D", "min_version": "1.0", "max_version": "1.1"}
    ],
    "C@1.6": [],
    "C@2.0": []
  },
  "root": {
    "package": "A",
    "min_version": "1.1",
    "max_version": "1.2"
  }
}
EOF

chmod -R 777 /home/user
