#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/remote_staging /home/user/templates

    cat << 'EOF' > /home/user/remote_staging/raw_data.csv
ID,Name,Email,Score,Department
1, Alice Smith , ALICE@example.com , 85 , Engineering
2,Bob Jones,bob.jones@example.com,,Sales
3, Charlie Brown, CHARLIE@Example.com, 92,Engineering
4, David , david@example.com, 78 , HR
5, Eve , EVE@test.com , , HR
6, Frank , frank@test.com, 82, Sales
EOF

    cat << 'EOF' > /home/user/templates/report.tmpl
# Daily Data Report

Total valid records processed: __TOTAL_RECORDS__

## Average Scores by Department
__DEPT_STATS__

End of Report.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
