#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app/tests/clean /app/tests/evil

    # Generate the audio file
    espeak -w /app/compliance_briefing.wav "Attention compliance team. Effective immediately, any graph query accessing the node label ShellCompany or traversing the relationship KICKBACK_TO is strictly prohibited. Update the auditors."

    # Create clean corpus
    cat << 'EOF' > /app/tests/clean/query1.cypher
MATCH (p:Person)-[:WORKS_FOR]->(c:Company) RETURN p, c
EOF
    cat << 'EOF' > /app/tests/clean/query2.cypher
MATCH (n:Employee) RETURN n LIMIT 10
EOF
    cat << 'EOF' > /app/tests/clean/query3.cypher
MATCH (a:Account)-[:TRANSFERRED_TO]->(b:Account) RETURN a, b
EOF

    # Create evil corpus
    cat << 'EOF' > /app/tests/evil/query1.cypher
MATCH (c1:Company)-[:KICKBACK_TO]->(c2:ShellCompany) RETURN c1
EOF
    cat << 'EOF' > /app/tests/evil/query2.cypher
MATCH (s:ShellCompany) RETURN s
EOF
    cat << 'EOF' > /app/tests/evil/query3.cypher
MATCH (a)-[:KICKBACK_TO]->(b) RETURN a
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
