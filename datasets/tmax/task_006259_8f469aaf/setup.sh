#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/users.csv
user_id,role,region
101,admin,US
102,user,EU
103,user,US
104,guest,AP
105,bot,US
EOF

    cat << 'EOF' > /home/user/data/access_logs.csv
timestamp,ip,user_id,endpoint,status
2023-10-01T10:00:00,192.168.1.1,102,/API/V1/data?id=1,200
2023-10-01T10:01:00,192.168.1.2,101,/Dashboard?theme=dark,200
2023-10-01T10:02:00,192.168.1.3,104,/login,200
2023-10-01T10:03:00,192.168.1.1,102,/api/v2/Submit?test=true,404
2023-10-01T10:04:00,192.168.1.5,105,/API/v2/scrape,403
2023-10-01T10:05:00,192.168.1.1,102,/api/v2/submit?force=1,500
2023-10-01T10:06:00,192.168.1.6,103,/API/V2/info,200
2023-10-01T10:07:00,192.168.1.5,105,/api/v2/scrape?v=2,403
2023-10-01T10:08:00,192.168.1.5,105,/api/v2/scrape?v=3,403
2023-10-01T10:09:00,192.168.1.1,102,/api/v2/submit,200
2023-10-01T10:10:00,192.168.1.2,101,/api/v2/admin,500
2023-10-01T10:11:00,192.168.1.3,104,/guestbook,200
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
