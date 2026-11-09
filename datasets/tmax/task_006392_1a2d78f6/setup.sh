#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create schema.json
    cat << 'EOF' > /home/user/schema.json
{
  "tables": [
    {
      "name": "users",
      "fks": []
    },
    {
      "name": "profiles",
      "fks": [{"column": "user_id", "references": "users"}]
    },
    {
      "name": "posts",
      "fks": [{"column": "author_id", "references": "users"}]
    },
    {
      "name": "comments",
      "fks": [
        {"column": "post_id", "references": "posts"},
        {"column": "user_id", "references": "users"}
      ]
    },
    {
      "name": "likes",
      "fks": [{"column": "comment_id", "references": "comments"}]
    },
    {
      "name": "tags",
      "fks": []
    },
    {
      "name": "post_tags",
      "fks": [
        {"column": "post_id", "references": "posts"},
        {"column": "tag_id", "references": "tags"}
      ]
    },
    {
      "name": "audit_logs",
      "fks": []
    },
    {
      "name": "system_settings",
      "fks": []
    }
  ]
}
EOF

    # Set permissions
    chmod -R 777 /home/user
