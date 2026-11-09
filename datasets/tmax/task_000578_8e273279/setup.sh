#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/tech_logs/2023/10/
    mkdir -p /home/user/tech_logs/2023/11/

    cat << 'EOF' > /home/user/tech_logs/2023/10/file1.log
=== DOC-1111 ===
Type: API_ADDITION
Content:
New endpoint added.
================
=== DOC-2048 ===
Type: API_DEPRECATION
Content:
Old auth system deprecated.
Use OAuth2.
================
EOF

    cat << 'EOF' > /home/user/tech_logs/2023/11/file2.log
=== DOC-8000 ===
Type: BUG_FIX
Content:
Fixed a typo.
================
=== DOC-3015 ===
Type: API_DEPRECATION
Content:
Removing legacy XML support.
================
=== DOC-9999 ===
Type: API_DEPRECATION
Content:
Sunset of v0.5.
================
EOF

    cat << 'EOF' > /home/user/authors.json
{
  "DOC-1111": {"author": "alice@example.com"},
  "DOC-2048": {"author": "bob@example.com"},
  "DOC-8000": {"author": "charlie@example.com"},
  "DOC-3015": {"author": "diana@example.com"},
  "DOC-9999": {"author": "eve@example.com"}
}
EOF

    chmod -R 777 /home/user
