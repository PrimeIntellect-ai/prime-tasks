#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/dataset

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "researcher_a": { "type": "string" },
      "researcher_b": { "type": "string" },
      "paper_a": { "type": "string" },
      "paper_b": { "type": "string" }
    },
    "required": ["researcher_a", "researcher_b", "paper_a", "paper_b"],
    "additionalProperties": false
  }
}
EOF

    cat << 'EOF' > /home/user/dataset/graph.jsonl
{"node_id": "r1", "node_type": "Researcher", "attributes": {"name": "Alice"}}
{"node_id": "r2", "node_type": "Researcher", "attributes": {"name": "Bob"}}
{"node_id": "r3", "node_type": "Researcher", "attributes": {"name": "Charlie"}}
{"node_id": "p1", "node_type": "Paper", "attributes": {"title": "Graph AI"}}
{"node_id": "p2", "node_type": "Paper", "attributes": {"title": "Neural Nets"}}
{"node_id": "p3", "node_type": "Paper", "attributes": {"title": "Data Mining"}}
{"source": "r1", "target": "p1", "rel_type": "AUTHORED"}
{"source": "r2", "target": "p2", "rel_type": "AUTHORED"}
{"source": "r3", "target": "p3", "rel_type": "AUTHORED"}
{"source": "p1", "target": "p2", "rel_type": "CITES"}
{"source": "p2", "target": "p3", "rel_type": "CITES"}
{"source": "r1", "target": "p3", "rel_type": "AUTHORED"}
{"source": "p3", "target": "p1", "rel_type": "CITES"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
