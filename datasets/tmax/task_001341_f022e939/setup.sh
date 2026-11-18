#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/cv_results.csv
learning_rate,batch_size,fold,validation_loss
0.01,32,1,0.4521
0.01,32,2,0.4710
0.01,32,3,
0.01,64,1,0.5032
0.01,64,2,0.5211
0.01,64,3,0.5100
0.001,32,1,0.3540
0.001,32,2,0.3610
0.001,32,3,0.3450
0.001,64,1,
0.001,64,2,0.4012
0.001,64,3,0.4134
0.005,16,1,
0.005,16,2,
0.005,16,3,0.3120
EOF

chmod -R 777 /home/user
