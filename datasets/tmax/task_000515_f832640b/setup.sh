#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget sed
    pip3 install pytest

    # Create directories
    mkdir -p /app/json-3.11.2/single_include/nlohmann/
    mkdir -p /app/data/clean/
    mkdir -p /app/data/evil/

    # Download nlohmann/json 3.11.2
    wget -qO /app/json-3.11.2/single_include/nlohmann/json.hpp https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp

    # Insert perturbation at line 50
    sed -i '50i #define std::size_t int' /app/json-3.11.2/single_include/nlohmann/json.hpp

    # Create clean corpus
    cat << 'EOF' > /app/data/clean/graph_1.json
[{"source": "A", "target": "B"}, {"source": "A", "target": "C"}, {"source": "A", "target": "D"}, {"source": "B", "target": "C"}]
EOF

    cat << 'EOF' > /app/data/clean/graph_2.json
[{"source": "U1", "target": "V1"}, {"source": "U1", "target": "V2"}, {"source": "U2", "target": "V1"}]
EOF

    # Create evil corpus
    cat << 'EOF' > /app/data/evil/bot_ring.json
[{"source": "N1", "target": "N2"}, {"source": "N2", "target": "N3"}, {"source": "N3", "target": "N4"}, {"source": "N4", "target": "N1"}]
EOF

    cat << 'EOF' > /app/data/evil/self_loop_spam.json
[{"source": "X", "target": "X"}, {"source": "Y", "target": "Y"}, {"source": "Z", "target": "Z"}, {"source": "X", "target": "Y"}]
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
