#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest openai-whisper

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate audio
    espeak -w /app/intercepted_call.wav "They are moving the compliance data into Project Chimera."

    # Create kg_hierarchy.json
    cat << 'EOF' > /app/kg_hierarchy.json
{
  "Titan": ["Apollo", "Atlas"],
  "Chimera": ["Gorgon", "Hydra"],
  "Hydra": ["Venom", "Scale"],
  "Apollo": ["Sun", "Chariot"]
}
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/query1.json
{"start_node": "Titan", "path": [{"target_node": "Apollo"}, {"target_node": "Sun"}]}
EOF

    cat << 'EOF' > /app/corpus/clean/query2.json
{"start_node": "Atlas", "path": []}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/query_evil1.json
{"start_node": "Atlas", "path": [{"target_node": "Chimera"}]}
EOF

    cat << 'EOF' > /app/corpus/evil/query_evil2.json
{"start_node": "Scale", "path": [{"target_node": "Venom"}]}
EOF

    cat << 'EOF' > /app/corpus/evil/query_evil3.json
{"start_node": "Chimera", "path": [{"target_node": "Gorgon"}]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
