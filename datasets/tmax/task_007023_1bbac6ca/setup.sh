#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_datasets

    cat << 'EOF' > /home/user/raw_datasets/dataset_1.txt
Quantum Computing Algorithms. Text discusses qubits, superposition, and entanglement in quantum states.
EOF

    cat << 'EOF' > /home/user/raw_datasets/dataset_2.txt
Machine Learning applied to Quantum Mechanics. Uses neural networks to predict quantum states and superposition.
EOF

    cat << 'EOF' > /home/user/raw_datasets/dataset_3.txt
Marine Biology. Studies on deep sea fish and coral reefs.
EOF

    cat << 'EOF' > /home/user/model_predictions.csv
dataset_1,quantum,superposition,apple
dataset_2,neural,quantum,car,space
dataset_3,deep,space,rocket,galaxy
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
