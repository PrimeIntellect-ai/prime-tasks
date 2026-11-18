#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_events.csv
id,timestamp,email,action,amount
1,1672531200,alice.smith@example.com,LOGIN,0
2,2023-01-01T01:30:00Z,bob@domain.com,PURCHASE,50
3,1672538400,charlie.brown@test.org,LOGOUT,0
4,2023-01-02T10:15:00Z,david.jones@example.com,PURCHASE,120
5,1672740000,eve@hacker.net,PURCHASE,300
EOF

    LBRACE="{"
    RBRACE="}"
    cat << EOF > /home/user/template.html
<html>
<body>
<h1>Daily Report</h1>
<p>Total Events: ${LBRACE}${LBRACE}TOTAL_EVENTS${RBRACE}${RBRACE}</p>
<p>Unique Domains: ${LBRACE}${LBRACE}UNIQUE_DOMAINS${RBRACE}${RBRACE}</p>
<p>Total Revenue: \$${LBRACE}${LBRACE}TOTAL_AMOUNT${RBRACE}${RBRACE}</p>
</body>
</html>
EOF

    chmod -R 777 /home/user
