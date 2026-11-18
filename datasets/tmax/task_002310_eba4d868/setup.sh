#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies for MongoDB and Go
    apt-get install -y curl gnupg golang-go

    # Install MongoDB 7.0 and Database Tools (for mongoimport)
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    apt-get update && apt-get install -y mongodb-org mongodb-database-tools

    # Create user
    useradd -m -s /bin/bash user || true

    # Create papers.json
    cat << 'EOF' > /home/user/papers.json
[
  { "_id": "P01", "title": "Intro to ML", "topics": ["Machine Learning", "AI"], "citations": ["P02", "P03"] },
  { "_id": "P02", "title": "Deep Learning basics", "topics": ["Machine Learning", "Neural Networks"], "citations": ["P04", "P05"] },
  { "_id": "P03", "title": "SVM theory", "topics": ["Machine Learning", "Math"], "citations": ["P06"] },
  { "_id": "P04", "title": "CNNs", "topics": ["Computer Vision", "Neural Networks"], "citations": ["P07", "P08"] },
  { "_id": "P05", "title": "RNNs", "topics": ["NLP", "Neural Networks"], "citations": [] },
  { "_id": "P06", "title": "Kernel Methods", "topics": ["Math"], "citations": ["P09"] },
  { "_id": "P07", "title": "ImageNet", "topics": ["Computer Vision"], "citations": [] },
  { "_id": "P08", "title": "ResNet", "topics": ["Computer Vision"], "citations": [] },
  { "_id": "P09", "title": "Advanced Kernels", "topics": ["Math"], "citations": [] },
  { "_id": "P10", "title": "Unrelated Database Paper", "topics": ["Databases"], "citations": ["P01"] }
]
EOF

    # Set permissions
    chmod -R 777 /home/user
