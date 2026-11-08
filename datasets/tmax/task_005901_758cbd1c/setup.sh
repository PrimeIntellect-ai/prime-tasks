#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip bzip2 tar gzip
    pip3 install pytest

    mkdir -p /home/user/raw_data_setup
    cd /home/user/raw_data_setup

    # Create CSV
    echo 'id,timestamp,value' > alpha.csv
    echo 'S1,1622540000,88.5' >> alpha.csv
    echo 'S2,1622540010,40.0' >> alpha.csv
    echo 'S9,1622540020,85.0' >> alpha.csv

    # Create JSON
    cat << 'EOF' > beta.json
[
  {"id": "S3", "value": 91.2},
  {"id": "S4", "value": 10.0},
  {"id": "S8", "value": 85.1}
]
EOF

    # Create XML
    cat << 'EOF' > gamma.xml
<readings>
  <reading>
    <id>S5</id>
    <value>99.9</value>
  </reading>
  <reading>
    <id>S6</id>
    <value>70.0</value>
  </reading>
</readings>
EOF

    # Nested archives
    zip batch1.zip alpha.csv beta.json
    tar -cjf batch2.tar.bz2 gamma.xml

    # Master archive
    tar -czf /home/user/data_dump.tar.gz batch1.zip batch2.tar.bz2

    # Cleanup
    cd /
    rm -rf /home/user/raw_data_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
