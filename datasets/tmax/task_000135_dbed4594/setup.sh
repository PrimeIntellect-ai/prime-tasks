#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ci_config.json
{
  "services": {
    "database": {
      "version": "3.0.1",
      "depends_on": []
    },
    "auth": {
      "version": "1.2.0",
      "depends_on": [{"name": "database", "requires": ">=3.0.0"}]
    },
    "api": {
      "version": "2.1.0",
      "depends_on": [
        {"name": "auth", "requires": ">=1.2.0"},
        {"name": "database", "requires": ">=3.0.0"}
      ]
    },
    "frontend": {
      "version": "1.0.5",
      "depends_on": [{"name": "api", "requires": ">=2.2.0"}]
    },
    "analytics": {
      "version": "1.0.0",
      "depends_on": [{"name": "database", "requires": ">=3.1.0"}]
    },
    "cache": {
      "version": "2.0.0",
      "depends_on": []
    }
  }
}
EOF

    cat << 'EOF' > /home/user/ci_update.patch
--- ci_config.json	2023-10-01 10:00:00.000000000 +0000
+++ ci_config.json	2023-10-01 10:05:00.000000000 +0000
@@ -9,7 +9,7 @@
       "depends_on": [{"name": "database", "requires": ">=3.0.0"}]
     },
     "api": {
-      "version": "2.1.0",
+      "version": "2.2.1",
       "depends_on": [
         {"name": "auth", "requires": ">=1.2.0"},
         {"name": "database", "requires": ">=3.0.0"}
EOF

    chmod -R 777 /home/user
