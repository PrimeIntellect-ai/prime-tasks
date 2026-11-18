#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc wget espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /opt/cJSON

    # Download cJSON
    wget https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.h -O /opt/cJSON/cJSON.h
    wget https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.c -O /opt/cJSON/cJSON.c

    # Generate audio file
    espeak -w /app/research_log.wav "Hello, this is the data organization memo. Our graph projection must only target the nodes labeled 'Dataset' and 'Experiment'. If any query attempts to project or match nodes labeled 'Admin' or 'Billing', it must be rejected. Furthermore, all match conditions in the NoSQL pipeline must use parameterized variables, meaning the match values must be strings that start with a dollar sign. Finally, the output projection must explicitly include the field 'confidence_score'."

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.json
{"$match": {"type": "Dataset", "status": "$status_param"}, "$project": {"confidence_score": 1, "data": 1}}
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.json
{"$match": {"type": "Experiment", "id": "$id_param"}, "$project": {"confidence_score": 1}}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.json
{"$match": {"type": "Admin", "status": "$status"}}
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.json
{"$match": {"type": "Dataset", "status": "active"}, "$project": {"confidence_score": 1}}
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.json
{"$match": {"type": "Experiment", "status": "$status_param"}, "$project": {"data": 1}}
EOF

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
