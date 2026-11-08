#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/hr_data.csv
emp_id,name,role,manager_id
E01,Alice,FTE,
E02,Bob,Contractor,E01
E03,Charlie,Contractor,E01
E04,Diana,FTE,E01
E05,Eve,Contractor,E04
E06,Frank,Contractor,E04
EOF

    cat << 'EOF' > /home/user/access_graph.jsonl
{"source": "E01", "relation": "MEMBER_OF", "target": "G_Admin"}
{"source": "E02", "relation": "MEMBER_OF", "target": "G_Dev"}
{"source": "E03", "relation": "MEMBER_OF", "target": "G_Test"}
{"source": "G_Test", "relation": "MEMBER_OF", "target": "G_Dev"}
{"source": "G_Dev", "relation": "MEMBER_OF", "target": "G_Prod"}
{"source": "G_Prod", "relation": "HAS_ACCESS", "target": "sys_finance"}
{"source": "E05", "relation": "MEMBER_OF", "target": "G_External"}
{"source": "G_External", "relation": "HAS_ACCESS", "target": "sys_marketing"}
{"source": "E06", "relation": "HAS_ACCESS", "target": "sys_finance"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
