#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/routes.txt
GET /health HealthCheck
GET /users/<int:user_id> GetUser
POST /users/<int:user_id>/update UpdateUser
DELETE /legacy/<str:resource_id> DeleteLegacy
EOF

    cat << 'EOF' > /home/user/workspace/py3_migration.patch
--- routes.txt
+++ routes.txt
@@ -2,3 +2,3 @@
 GET /users/<int:user_id> GetUser
 POST /users/<int:user_id>/update UpdateUser
-DELETE /legacy/<str:resource_id> DeleteLegacy
+PUT /users/<int:user_id>/profile/<str:profile_type> UpdateProfile
EOF

    chmod -R 777 /home/user
