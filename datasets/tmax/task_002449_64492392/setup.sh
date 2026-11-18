#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users_run1.csv
user_id,name,email,signup_date
1,Alice Smith,alice.smith@example.com,01/15/2023
2,Bob Jones,bjones@test.org,2023-02-20
4,Diana Prince,diana@themyscira.gov,12-05-2022
EOF

    cat << 'EOF' > /home/user/data/users_run2.csv
user_id,name,email,signup_date
2,Bob Jones,bjones@test.org,2023-02-20
3,Charlie Brown,cbrown@peanuts.com,03/10/2023
5,Ed,ed@short.com,05/12/2023
EOF

    chmod -R 777 /home/user
