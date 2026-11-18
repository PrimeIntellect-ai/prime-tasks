#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/papers.jsonl
{"paper_id": "P01", "year": 2011, "citations": ["P02", "P03", "P99"]}
{"paper_id": "P02", "year": 2012, "citations": ["P03"]}
{"paper_id": "P03", "year": 2015, "citations": ["P01"]}
{"paper_id": "P04", "year": 2009, "citations": ["P01"]}
{"paper_id": "P05", "year": 2018, "citations": ["P06", "P07"]}
{"paper_id": "P06", "year": 2019, "citations": ["P05", "P01"]}
{"paper_id": "P07", "year": 2020, "citations": []}
{"paper_id": "P08", "year": 2021, "citations": ["P07", "P05"]}
EOF

    chmod -R 777 /home/user
