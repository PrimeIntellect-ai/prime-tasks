#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "shard_id": { "type": "string" },
      "avg_duration": { "type": "number" },
      "failure_count": { "type": "integer" }
    },
    "required": ["shard_id", "avg_duration", "failure_count"],
    "additionalProperties": false
  }
}
EOF

    sqlite3 /home/user/backups.db <<'EOF'
CREATE TABLE backup_logs (
    id INTEGER PRIMARY KEY,
    shard_id TEXT,
    backup_date TEXT,
    duration_seconds INTEGER,
    status TEXT
);
INSERT INTO backup_logs (shard_id, backup_date, duration_seconds, status) VALUES 
('shard-01', '2023-10-01T00:00:00Z', 100, 'SUCCESS'),
('shard-01', '2023-10-02T00:00:00Z', 200, 'FAILED'),
('shard-01', '2023-10-03T00:00:00Z', 310, 'SUCCESS'),
('shard-01', '2023-10-04T00:00:00Z', 320, 'SUCCESS'),
('shard-01', '2023-10-05T00:00:00Z', 330, 'SUCCESS'),

('shard-02', '2023-10-01T00:00:00Z', 400, 'SUCCESS'),
('shard-02', '2023-10-02T00:00:00Z', 400, 'SUCCESS'),
('shard-02', '2023-10-03T00:00:00Z', 400, 'SUCCESS'),
('shard-02', '2023-10-04T00:00:00Z', 400, 'SUCCESS'),

('shard-03', '2023-10-01T00:00:00Z', 100, 'SUCCESS'),
('shard-03', '2023-10-02T00:00:00Z', 100, 'FAILED'),
('shard-03', '2023-10-03T00:00:00Z', 100, 'FAILED'),
('shard-03', '2023-10-04T00:00:00Z', 100, 'SUCCESS'),
('shard-03', '2023-10-05T00:00:00Z', 100, 'SUCCESS');
EOF

    chmod -R 777 /home/user
