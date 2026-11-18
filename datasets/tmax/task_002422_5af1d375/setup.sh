#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/v1.sym
DEF init_system
DEF load_config
DEF start_worker
ALIAS run_worker start_worker
DROP load_config
DEF parse_args
EOF

    cat << 'EOF' > /home/user/update.patch
--- v1.sym
+++ v2.sym
@@ -2,5 +2,6 @@
 DEF load_config
 DEF start_worker
 ALIAS run_worker start_worker
-DROP load_config
+DEF cleanup_system
 DEF parse_args
+DROP start_worker
EOF

    chmod -R 777 /home/user
