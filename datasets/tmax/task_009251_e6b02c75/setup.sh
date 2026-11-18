#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_feedback.txt
1670000000|U001|alice.smith@example.com|Great service!! Highly recommend.
1670000005|U002|bob.jones@work.net|Terrible, just terrible!
1670000000|U001|alice.smith@example.com|Great service!! Highly recommend.
1670000010|U003|charlie@domain.org|Okay experience.
1670000015|U004|diana.prince@mail.com|Great service highly recommend
1670000020|U005|eve@test.com|I loved it!
1670000025|U006|frank@test.com|i LOVED it!!!
EOF

    chmod -R 777 /home/user
