#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.csv
id,name,email,ssn,country
1,John Doe,JOHN@EXAMPLE.COM,123-45-6789,US
2,Jane Doe,jane@example.com,234-56-7890,CA
3,Bob Smith,BOB@EXAMPLE.COM,345-67-8901,UK
4,Alice Jones,alice@example.com,456-78-9012,AU
5,Duplicate John,john@example.com,567-89-0123,US
6,Even Guy,even@example.com,678-90-1234,US
7,Odd Guy,ODD@example.com,789-01-2345,US
8,Another Even,test@test.com,999-99-9999,DE
9,Charlie,CHARLIE@TEST.COM,111-22-3333,FR
11,Charlie Dup,charlie@test.com,222-33-4444,IT
EOF

    chmod -R 777 /home/user
