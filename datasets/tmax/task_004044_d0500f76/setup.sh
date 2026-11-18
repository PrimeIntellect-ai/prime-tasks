#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/routes

    cat << 'EOF' > /home/user/routes/frontend.route
GET /home?lang=en home_handler 10
POST /login?method=oauth&retry=true login_handler 20
EOF

    cat << 'EOF' > /home/user/routes/backend.route
GET /api/data?filter=all api_handler 50
POST /login?method=basic legacy_login 20
EOF

    cat << 'EOF' > /home/user/routes/legacy.route
GET /home?lang=fr&theme=dark old_home 5
DELETE /api/data api_delete 100
EOF

    cat << 'EOF' > /home/user/routes/previous.txt
DELETE /api/data [] -> api_delete (Weight: 100)
GET /api/data [filter] -> old_api (Weight: 50)
GET /home [lang] -> home_handler (Weight: 10)
PUT /upload [] -> upload_handler (Weight: 5)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
