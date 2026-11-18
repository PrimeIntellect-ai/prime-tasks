#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /home/user/recommender

    # Create users.csv
    cat << 'EOF' > /home/user/data/users.csv
user_id,department
1,CS
2,Math
3,Physics
4,CS
EOF

    # Create train_ratings.csv
    cat << 'EOF' > /home/user/data/train_ratings.csv
user_id,paper_id,rating
1,101,5
1,102,
1,103,4
2,101,4
2,102,5
2,103,2
3,101,
3,102,4
3,103,5
4,101,2
4,102,3
4,103,
EOF

    # Create val_ratings.csv
    cat << 'EOF' > /home/user/data/val_ratings.csv
user_id,paper_id,rating
1,102,3
3,101,4
4,103,2
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
