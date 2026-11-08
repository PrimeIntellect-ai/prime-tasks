#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_feedback.txt
1|alice@example.com|2023-10-01|Great service!
2|bob@work.org|2023-10-02|Needs improvement.
3|test@test.com|2023-10-03|Great service!
4|charlie@test.net|2023-10-04|Terrible experience, very slow.
5|dave@xyz.co|2023-10-05|Needs improvement.
6|eve@secure.io|2023-10-06|Perfect.
EOF

    chmod -R 777 /home/user
