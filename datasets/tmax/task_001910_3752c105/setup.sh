#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/changelog.log
Commit: 7f8a9b2
Author: Bob Engineer
Date: 2023-10-10
Message:
  Fixed memory leak in auth module.
---
Commit: 3c4d5e6
Author: Alice Writer
Date: 2023-10-11
Message:
  Initial draft of API endpoints.
  Formatting fixes.
---
Commit: 9a8b7c6
Author: Charlie Dev
Date: 2023-10-12
Message:
  Refactored database schema.
---
Commit: 1d2e3f4
Author: Alice Writer
Date: 2023-10-14
Message:
  Added Webhook documentation.
  Fixed typos in overview.
  Clarified rate limits.
---
EOF

    mkdir -p /tmp/setup/drafts
    echo "Draft 1" > "/tmp/setup/drafts/Release Notes v1.txt"
    echo "Draft 2" > "/tmp/setup/drafts/API Spec Draft.txt"
    echo "Draft 3" > "/tmp/setup/drafts/User Guide.txt"
    cd /tmp/setup
    tar -czf drafts.tar.gz drafts/
    zip -r /home/user/docs_archive.zip drafts.tar.gz
    rm -rf /tmp/setup

    chmod -R 777 /home/user
