#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.txt
TxID: A100 | User: Alice Smith | Card: 1111222233334444 | Amount: 100.00
TxID: B200 | User: Bob Jones | Card: 5555666677778888 | Amount: 150.00
TxID: A100 | User: Alice Smith | Card: 1111222233334444 | Amount: 100.00
TxID: C300 | User: Charlie B | Card: 9999000011112222 | Amount: 200.00
TxID: D400 | User: Dana White | Card: 1234123412341234 | Amount: 50.00
TxID: B200 | User: Bob Jones | Card: 5555666677778888 | Amount: 150.00
TxID: E500 | User: Eve Black | Card: 4321432143214321 | Amount: 300.00
EOF

    chmod -R 777 /home/user
