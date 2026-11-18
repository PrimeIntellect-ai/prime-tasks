#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq xmlstarlet
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create config.json
    cat << 'EOF' > /home/user/config.json
{
  "json": {
    "name_filter": ".metadata.title",
    "count_filter": ".data.total_rows"
  },
  "csv": {
    "name_column": 2,
    "count_column": 4
  },
  "xml": {
    "name_xpath": "//dataset/title",
    "count_xpath": "//dataset/records"
  }
}
EOF

    # Create datasets directory and sample files
    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/sample1.json
{"metadata": {"title": "GenomeDB"}, "data": {"total_rows": 5000}}
EOF

    cat << 'EOF' > /home/user/datasets/sample2.csv
1,ClimateData,xyz,12500,active
EOF

    cat << 'EOF' > /home/user/datasets/sample3.xml
<root><dataset><title>OceanTemps</title><records>8900</records></dataset></root>
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
