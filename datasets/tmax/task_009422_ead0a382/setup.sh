#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
id,name,department
1,Alice,Sales
2,Bob,Sales
3,Charlie,Sales
4,David,Engineering
5,Eve,Engineering
6,Frank,Engineering
7,Grace,HR
EOF

    cat << 'EOF' > /home/user/emails.csv
sender_id,receiver_id,timestamp
1,2,1600000000
2,3,1600000010
3,1,1600000020
4,5,1600000030
5,6,1600000040
6,4,1600000050
1,4,1600000060
1,5,1600000070
1,6,1600000080
1,2,1600000090
4,5,1600000100
EOF

    chmod -R 777 /home/user
