#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/waf_logs

    cat << 'EOF' > /home/user/waf_logs/us_east.log
[2023-10-01T10:00:00Z] GET /api/v1/users?id=123&data=bWFsaWNpb3VzX2ludGVudF9zcWxp
[2023-10-01T10:05:00Z] POST /api/v2/auth?data=YmVuaWduX3BheWxvYWQ=
[2023-10-01T10:15:00Z] GET /health?data=c29tZV9yYW5kb21fdmFsdWU=
[2023-10-01T10:20:00Z] GET /api/v1/admin?data=bWFsaWNpb3VzX2ludGVudF9yY2U=
EOF

    cat << 'EOF' > /home/user/waf_logs/eu_west.log
[2023-10-01T09:50:00Z] GET /login?data=bWFsaWNpb3VzX2ludGVudF9zcWxp
[2023-10-01T10:10:00Z] GET /api/v1/search?q=test&data=bWFsaWNpb3VzX2ludGVudF94c3M=
[2023-10-01T09:45:00Z] POST /api/v2/auth?data=bm90aGluZ190b19zZWVfaGVyZQ==
[2023-10-01T10:25:00Z] GET /admin/dashboard?data=bWFsaWNpb3VzX2ludGVudF9yY2U=
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
