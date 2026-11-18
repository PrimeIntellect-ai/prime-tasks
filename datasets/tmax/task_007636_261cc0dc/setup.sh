#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/migration

    cat << 'EOF' > /home/user/migration/input.json
{
  "101": {"name": "Alice", "role": "Admin"},
  "102": {"name": "Bob", "role": "User"},
  "103": {"name": "Charlie", "role": "User"}
}
EOF

    cat << 'EOF' > /home/user/migration/migrate.py
import json
import sys

def migrate(input_file, output_file):
    with open(input_file, 'r') as f:
        data = json.load(f)

    new_data = []
    # Legacy Python 2 dictionary iteration
    for k, v in data.iteritems():
        print "Migrating user ID:", k
        new_data.append({
            "new_id": int(k),
            "full_name": v["name"],
            "is_admin": v["role"] == "Admin"
        })

    with open(output_file, 'w') as f:
        json.dump(new_data, f)

if __name__ == '__main__':
    migrate(sys.argv[1], sys.argv[2])
EOF

    cat << 'EOF' > /home/user/migration/versions.txt
v1.0.1 - Initial release
v1.1.0 - Bugfixes and performance improvements
v1.9.5 - Final Python 2 support updates
v2.0.0-alpha - Python 3 experimental rewrite
v2.0.0-beta - Python 3 beta testing
v2.0.1 - Stable Python 3 support added
v2.1.0 - Additional features
v3.0.0 - Breaking changes
EOF

    chown -R user:user /home/user/migration
    chmod -R 777 /home/user
