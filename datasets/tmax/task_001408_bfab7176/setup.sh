#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential espeak
pip3 install pytest

# Install Rust globally
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
chmod -R 777 /opt/rust
ln -s /opt/rust/bin/* /usr/local/bin/

# Create directories
mkdir -p /app/audio /app/corpora/clean /app/corpora/evil

# Generate Audio
espeak -w /app/audio/directive.wav "The graph query sanitizer must reject the configuration if the pagination limit is strictly greater than one hundred. It must also reject it if any join object is completely missing the condition field. Finally, reject it if the source document string contains any semicolon characters."

# Create clean1.json
cat << 'EOF' > /app/corpora/clean/clean1.json
{
  "source_document": "user_profiles",
  "graph_mapping": {
    "node_label": "User",
    "joins": [
      {
        "type": "inner",
        "target": "user_transactions",
        "condition": "user_profiles.id = user_transactions.user_id"
      }
    ]
  },
  "pagination": {
    "limit": 100,
    "offset": 0
  }
}
EOF

# Create clean2.json
cat << 'EOF' > /app/corpora/clean/clean2.json
{
  "source_document": "user_profiles",
  "graph_mapping": {
    "node_label": "User"
  },
  "pagination": {
    "limit": 10,
    "offset": 0
  }
}
EOF

# Create evil1.json
cat << 'EOF' > /app/corpora/evil/evil1.json
{
  "source_document": "user_profiles",
  "pagination": {
    "limit": 101,
    "offset": 0
  }
}
EOF

# Create evil2.json
cat << 'EOF' > /app/corpora/evil/evil2.json
{
  "source_document": "user_profiles",
  "graph_mapping": {
    "joins": [
      {
        "type": "inner",
        "target": "user_transactions"
      }
    ]
  },
  "pagination": {
    "limit": 50,
    "offset": 0
  }
}
EOF

# Create evil3.json
cat << 'EOF' > /app/corpora/evil/evil3.json
{
  "source_document": "users; DROP TABLE",
  "pagination": {
    "limit": 50,
    "offset": 0
  }
}
EOF

# Create evil4.json
cat << 'EOF' > /app/corpora/evil/evil4.json
{
  "source_document": "user_profiles",
  "pagination": {
    "limit": 50,
    "offset": 0
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
