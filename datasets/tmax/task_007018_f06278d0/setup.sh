#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq libc6-dev
    pip3 install pytest

    mkdir -p /home/user/dataset
    cat << 'EOF' > /home/user/dataset/edges.txt
MachineLearning DeepLearning
MachineLearning NeuralNetworks
MachineLearning LinearRegression
NeuralNetworks CNN
NeuralNetworks RNN
DataScience MachineLearning
DataScience Statistics
Statistics Probability
Statistics HypothesisTesting
Probability BayesianInference
Probability MarkovChains
Probability RandomVariables
DeepLearning CNN
DeepLearning RNN
DeepLearning GAN
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
