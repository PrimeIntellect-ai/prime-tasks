#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate audio memo
    espeak -w /app/incident_memo.wav "Hey, it's Alex. For the new backup system, ensure every dependency graph is a strictly Directed Acyclic Graph. No cycles allowed. Also, the absolute root of every graph—meaning the node that has no outgoing dependency edges—must have the exact ID 'global_state_db'. Finally, no node can be more than 4 hops away from the root. Any graph breaking these rules is invalid."

    # Generate JSON corpus
    cat << 'EOF' > /tmp/gen_json.py
import json
import os

clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

# Clean 1: 1 hop
c1 = {"nodes": [{"id": "global_state_db", "type": "relational"}, {"id": "n1", "type": "document"}], "edges": [{"source": "n1", "target": "global_state_db"}]}
# Clean 2: 2 hops
c2 = {"nodes": [{"id": "global_state_db", "type": "relational"}, {"id": "n1", "type": "document"}, {"id": "n2", "type": "relational"}], "edges": [{"source": "n1", "target": "global_state_db"}, {"source": "n2", "target": "n1"}]}
# Clean 3: 3 hops
c3 = {"nodes": [{"id": "global_state_db", "type": "relational"}, {"id": "n1", "type": "document"}, {"id": "n2", "type": "relational"}, {"id": "n3", "type": "document"}], "edges": [{"source": "n1", "target": "global_state_db"}, {"source": "n2", "target": "n1"}, {"source": "n3", "target": "n2"}]}
# Clean 4: 4 hops
c4 = {"nodes": [{"id": "global_state_db", "type": "relational"}, {"id": "n1", "type": "document"}, {"id": "n2", "type": "relational"}, {"id": "n3", "type": "document"}, {"id": "n4", "type": "document"}], "edges": [{"source": "n1", "target": "global_state_db"}, {"source": "n2", "target": "n1"}, {"source": "n3", "target": "n2"}, {"source": "n4", "target": "n3"}]}
# Clean 5: Branching
c5 = {"nodes": [{"id": "global_state_db", "type": "relational"}, {"id": "n1", "type": "document"}, {"id": "n2", "type": "relational"}], "edges": [{"source": "n1", "target": "global_state_db"}, {"source": "n2", "target": "global_state_db"}]}

for i, c in enumerate([c1, c2, c3, c4, c5]):
    with open(os.path.join(clean_dir, f"clean_{i+1}.json"), "w") as f:
        json.dump(c, f)

# Evil 1: Cycle
e1 = {"nodes": [{"id": "global_state_db", "type": "relational"}, {"id": "n1", "type": "document"}], "edges": [{"source": "n1", "target": "global_state_db"}, {"source": "global_state_db", "target": "n1"}]}
# Evil 2: Wrong root
e2 = {"nodes": [{"id": "auth_db", "type": "relational"}, {"id": "n1", "type": "document"}], "edges": [{"source": "n1", "target": "auth_db"}]}
# Evil 3: Path length 5
e3 = {"nodes": [{"id": "global_state_db", "type": "relational"}, {"id": "n1", "type": "document"}, {"id": "n2", "type": "relational"}, {"id": "n3", "type": "document"}, {"id": "n4", "type": "document"}, {"id": "n5", "type": "document"}], "edges": [{"source": "n1", "target": "global_state_db"}, {"source": "n2", "target": "n1"}, {"source": "n3", "target": "n2"}, {"source": "n4", "target": "n3"}, {"source": "n5", "target": "n4"}]}
# Evil 4: Disconnected (n2 has no edges, thus is a second root)
e4 = {"nodes": [{"id": "global_state_db", "type": "relational"}, {"id": "n1", "type": "document"}, {"id": "n2", "type": "relational"}], "edges": [{"source": "n1", "target": "global_state_db"}]}
# Evil 5: Multiple roots explicitly
e5 = {"nodes": [{"id": "global_state_db", "type": "relational"}, {"id": "other_db", "type": "document"}, {"id": "n1", "type": "document"}], "edges": [{"source": "n1", "target": "global_state_db"}]}

for i, e in enumerate([e1, e2, e3, e4, e5]):
    with open(os.path.join(evil_dir, f"evil_{i+1}.json"), "w") as f:
        json.dump(e, f)
EOF

    python3 /tmp/gen_json.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
