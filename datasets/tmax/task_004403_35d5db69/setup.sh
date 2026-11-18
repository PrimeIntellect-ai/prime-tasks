#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/ecommerce.csv
id,name,about,purchases
E1,Alice Smith,Data scientist and AI enthusiast,laptop;mouse
E2,Bob Jones,Loves cooking and baking cakes,pan;spatula
E3,Charlie Brown,Just a regular guy,shirt
E4,Diana Prince,Warrior princess from Themyscira,sword;shield
EOF

    cat << 'EOF' > /home/user/data/forum.csv
fid,username,signature,topics
F1,alicesmith,Data scientist and AI enthusiast,machine learning;deep learning
F2,bobby_j,Cooking and baking cakes lover,recipes;kitchenware
F3,charlie,Skateboarder,sports
F4,dianap,Amazon warrior princess,history;combat
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
