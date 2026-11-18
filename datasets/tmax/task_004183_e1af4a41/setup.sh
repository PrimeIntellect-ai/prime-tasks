#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.txt
2023-11-01 08:00:00 UTC | sens-01 | 10.0 | All clear!
2023-11-01T08:01:00Z | SENS-01 | 15.0 | minor issues...
2023-11-01 08:02:00 UTC | Sens-01 | 20.0 | ERROR: 404
2023-11-01 08:03:00 UTC | sens-01 | 10.0 | fixed.
2023-11-01T08:04:00Z | sens-01 | 12.0 | OK 
EOF

    chmod -R 777 /home/user
