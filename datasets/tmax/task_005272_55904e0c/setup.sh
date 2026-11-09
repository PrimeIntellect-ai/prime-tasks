#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo gawk
    pip3 install pytest

    mkdir -p /home/user/model_eval
    cd /home/user/model_eval

    cat << 'EOF' > cv_results.csv
fold_id,k,y_true,y_pred
1,3.0,1,1
1,3.0,0,1
1,3.0,1,0
1,3.0,0,0
2,3.0,1,1
2,3.0,0,1
2,3.0,1,0
2,3.0,0,0
3,3.0,1,1
3,3.0,0,1
3,3.0,1,0
3,3.0,0,0
1,5.0,1,1
1,5.0,0,0
1,5.0,1,1
1,5.0,0,1
2,5.0,1,1
2,5.0,0,0
2,5.0,1,1
2,5.0,0,1
3,5.0,1,1
3,5.0,0,0
3,5.0,1,1
3,5.0,0,0
1,7.0,1,1
1,7.0,0,1
1,7.0,1,1
1,7.0,0,0
2,7.0,1,1
2,7.0,0,1
2,7.0,1,1
2,7.0,0,0
3,7.0,1,1
3,7.0,0,1
3,7.0,1,1
3,7.0,0,0
EOF

    echo "id,feature_val" > inference_data.csv
    for i in $(seq 1 5000); do
      echo "$i,$(awk -v seed=$i 'BEGIN{srand(seed); print rand() * 10}')" >> inference_data.csv
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
