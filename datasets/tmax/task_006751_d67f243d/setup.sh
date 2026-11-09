#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make patch
    pip3 install pytest

    mkdir -p /home/user/artifact_pipeline

    cat << 'EOF' > /home/user/artifact_pipeline/artifacts.json
[
  {
    "id": "build-101",
    "coverage": 0.85,
    "complexity": 2,
    "tests_passed": 30
  },
  {
    "id": "build-102",
    "coverage": 0.90,
    "complexity": 4,
    "tests_passed": 45
  },
  {
    "id": "build-103",
    "coverage": 0.20,
    "complexity": 5,
    "tests_passed": 10
  }
]
EOF

    cat << 'EOF' > /home/user/artifact_pipeline/update.patch
--- artifacts.json
+++ artifacts.json
@@ -7,8 +7,8 @@
   },
   {
     "id": "build-102",
-    "coverage": 0.90,
-    "complexity": 4,
+    "coverage": 0.95,
+    "complexity": 3,
     "tests_passed": 45
   },
   {
EOF

    cat << 'EOF' > /home/user/artifact_pipeline/formula.txt
(coverage * 100) / (complexity ^ 2) + tests_passed
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/artifact_pipeline
    chmod -R 777 /home/user
