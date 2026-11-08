#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang zip tar gzip
    pip3 install pytest

    mkdir -p /home/user/docs_raw
    mkdir -p /home/user/docs_temp

    # Create docA.md
    cat << 'EOF' > /home/user/docs_temp/docA.md
# API Documentation Part 1
[DRAFT_WATERMARK_12345]
This is the documentation for the API endpoint.

> Config Start
endpoint: https://api.example.com/v1
timeout: 30s
> Config End

More text here. [DRAFT_WATERMARK_999]
EOF

    # Create docB.md
    cat << 'EOF' > /home/user/docs_temp/docB.md
# API Documentation Part 2
Here are the retry parameters. [DRAFT_WATERMARK_001]

> Config Start
retry_count: 5
backoff_multiplier: 1.5
> Config End

End of doc.
EOF

    # Create tar archives
    cd /home/user/docs_temp
    tar -czf /home/user/docs_raw/part1.tar.gz docA.md
    tar -czf /home/user/docs_raw/part2.tar.gz docB.md

    # Clean temp
    rm -rf /home/user/docs_temp

    # Create INI file
    cat << 'EOF' > /home/user/doc_rules.ini
[extraction]
start_marker = > Config Start
end_marker = > Config End
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
