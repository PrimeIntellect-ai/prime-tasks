#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential ffmpeg espeak
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/usr/local/cargo/bin:$PATH"
    chmod -R a+w /usr/local/cargo /usr/local/rustup

    # Create directories
    mkdir -p /app/corpus/evil /app/corpus/clean

    # Generate audio file
    espeak -w /app/dba_instructions.wav "We need to block queries that cause Cartesian products. Reject any Cypher query that contains a MATCH clause with a comma separating two or more disconnected nodes, for example MATCH open parenthesis a close parenthesis comma open parenthesis b close parenthesis. Accept queries where nodes are connected by relationships or where there is no comma separated MATCH."

    # Populate corpus
    cat << 'EOF' > /app/corpus/evil/evil1.cypher
MATCH (a), (b) RETURN a, b
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.cypher
MATCH (user:User), (post:Post) WHERE user.id = post.author_id RETURN user, post
EOF

    cat << 'EOF' > /app/corpus/clean/clean1.cypher
MATCH (a)-[:FRIEND]->(b) RETURN a, b
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.cypher
MATCH (user:User {id: 123}) RETURN user
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
