#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sales.csv
TransactionID,Date,Region,Category,Amount,SalesRep
101,2023-01-01,North,Electronics,500,Alice
102,2023-01-02,South,Books,150,Bob
103,2023-01-03,West,Electronics,800,Charlie
104,2023-01-04,West,Clothing,200,Diana
105,2023-01-05,East,Books,300,Eve
106,2023-01-06,West,Electronics,1200,Charlie
107,2023-01-07,North,Clothing,100,Alice
108,2023-01-08,West,Books,250,Diana
109,2023-01-09,South,Electronics,900,Bob
110,2023-01-10,West,Clothing,180,Charlie
111,2023-01-11,West,Books,400,Diana
112,2023-01-12,East,Electronics,600,Eve
113,2023-01-13,West,Clothing,220,Charlie
114,2023-01-14,North,Books,350,Alice
115,2023-01-15,West,Electronics,950,Diana
116,2023-01-16,South,Clothing,130,Bob
117,2023-01-17,West,Books,500,Charlie
EOF

    chown user:user /home/user/sales.csv
    chmod -R 777 /home/user
