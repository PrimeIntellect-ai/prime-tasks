#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/data/eval.csv
id,f1,y_true
1,10.0,5.0
2,20.0,7.0
3,30.0,9.0
4,40.0,11.0
EOF

    cat << 'EOF' > /home/user/artifacts/preds_A.csv
id,y_pred
1,5.1
2,7.2
3,9.0
4,10.0
EOF

    cat << 'EOF' > /home/user/artifacts/preds_B.csv
id,y_pred
1,4.0
2,6.0
3,8.0
4,8.0
EOF

    cat << 'EOF' > /home/user/artifacts/preds_C.csv
id,y_pred
1,5.5
2,7.5
3,9.5
4,11.5
EOF

    cat << 'EOF' > /home/user/artifacts/metadata.json
{
  "A": {"num_features": 10},
  "B": {"num_features": 2},
  "C": {"num_features": 5}
}
EOF

    chmod -R 777 /home/user
