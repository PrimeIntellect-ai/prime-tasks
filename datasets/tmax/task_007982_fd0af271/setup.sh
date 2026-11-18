#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Initialize the sqlite database
    sqlite3 /home/user/builds.db <<EOF
CREATE TABLE legacy_builds(id INTEGER PRIMARY KEY, repository TEXT, build_data TEXT);
INSERT INTO legacy_builds (repository, build_data) VALUES ('github.com/org/repo1', '{"lang": "node", "command": "npm run build", "timeout": 300}');
INSERT INTO legacy_builds (repository, build_data) VALUES ('github.com/org/repo2', '{"lang": "python", "command": "pip install -r req.txt && pytest", "timeout": 600}');
EOF

    # Create dummy input for testing generate_env.sh
    cat << 'EOF' > /home/user/test_env.json
{
  "project": "test",
  "env": {
    "ZOO": "animals",
    "APP_PORT": "8080",
    "DEBUG": "true"
  }
}
EOF

    chmod -R 777 /home/user
