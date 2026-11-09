#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/day1.csv
id,feedback
1,The product is great!
2,I love the new features.
3,Very fast and reliable.
4,Standard usage, no issues.
5,It works fine for my daily tasks.
EOF

    cat << 'EOF' > /home/user/day2.json
[
  {"id": 6, "comment": "I love the new features."},
  {"id": 7, "comment": "Wait, the floob widget is broken."},
  {"id": 8, "comment": "floob widget keeps crashing."},
  {"id": 9, "comment": "Why is the floob widget so slow?"},
  {"id": 10, "comment": "Fix the floob widget!"},
  {"id": 11, "comment": "floob widget is the worst."},
  {"id": 12, "comment": "Also the zarkon integration failed."},
  {"id": 13, "comment": "zarkon is down."},
  {"id": 14, "comment": "zarkon zarkon zarkon!"},
  {"id": 15, "comment": "I cannot connect to zarkon."}
]
EOF

    chmod -R 777 /home/user
