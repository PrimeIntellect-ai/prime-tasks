#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch
    pip3 install pytest hypothesis

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/migrate.py
import statistics

def migrate_v1_to_v2(v1_data):
    v2_data = {}
    v2_data["record_id"] = v1_data["id"]
    # BUG: using sum instead of mean
    v2_data["mean"] = sum(v1_data["data"]) 
    v2_data["normalized_data"] = [x - v2_data["mean"] for x in v1_data["data"]]
    return v2_data
EOF

    cat << 'EOF' > /home/user/fix.patch
--- migrate.py
+++ migrate.py
@@ -6,3 +6,2 @@
-    # BUG: using sum instead of mean
-    v2_data["mean"] = sum(v1_data["data"]) 
+    v2_data["mean"] = statistics.mean(v1_data["data"]) 
     v2_data["normalized_data"] = [x - v2_data["mean"] for x in v1_data["data"]]
EOF

    chmod -R 777 /home/user
