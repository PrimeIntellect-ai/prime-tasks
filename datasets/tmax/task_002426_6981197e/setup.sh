#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    # Create user
    useradd -m -s /bin/bash user || true

    # Create raw_logs directory
    mkdir -p /home/user/raw_logs

    # Populate raw_logs
    cat << 'EOF' > /home/user/raw_logs/batch1.csv
id,time,text
1,1622505600,Hello World!
2,2021-06-01T00:00:00Z,Hello world?
3,1622505605,Another message...
EOF

    cat << 'EOF' > /home/user/raw_logs/batch2.json
[
  {"id": 2, "time": 1622505600, "text": "Hello world?"},
  {"id": 4, "time": "2021-06-01T00:00:10Z", "text": "Test message!!!"},
  {"id": 5, "time": 1622505615, "text": "   Extra    spaces   "}
]
EOF

    cat << 'EOF' > /home/user/raw_logs/batch3.csv
id,time,text
1,2021-06-01T00:00:00Z,Hello World!
5,1622505615,extra spaces
EOF

    # Set permissions
    chmod -R 777 /home/user
