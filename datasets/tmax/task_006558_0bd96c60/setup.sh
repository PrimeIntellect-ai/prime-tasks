#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron gawk coreutils findutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/reports

    cat << 'EOF' > /home/user/reports/us_east.csv
service_name, day1, day2, day3
 AuthSvc , 1.5 , 2.0 , invalid
 PaymentSvc, 0.5, -1.0, 1.0
 InventorySvc, 3.0, 3.0, 4.0
EOF

    cat << 'EOF' > /home/user/reports/eu_west.csv
service_name, day1, day2, day3
 AuthSvc, 1.0, , 2.5
 PaymentSvc, 5.0, 5.0, 5.0
 NotificationSvc, 0.1, 0.2, 0.3
EOF

    cat << 'EOF' > /home/user/reports/ap_south.csv
service_name, day1, day2, day3
 InventorySvc, 2.0, 1.5, 
 CacheSvc, 10.0, 2.0, 0.5
 AuthSvc, 0.5, 0.5, 0.5
EOF

    chown -R user:user /home/user/reports
    chmod -R 777 /home/user
