#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/loc_views.csv
timestamp,lang,views
2023-10-01T10:00:00Z,fr,150
2023-10-01T15:30:00Z,de,200
2023-10-01T23:59:59Z,fr,50
2023-10-02T09:15:00Z,fr,100
2023-10-03T08:00:00Z,es,300
EOF

    cat << 'EOF' > /home/user/workspace/loc_edits.json
[
  {"time": "2023-10-01T12:00:00Z", "fr": 5, "de": null, "es": 2},
  {"time": "2023-10-02T11:00:00Z", "de": 10},
  {"time": "2023-10-03T14:00:00Z", "es": 15, "fr": null}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
