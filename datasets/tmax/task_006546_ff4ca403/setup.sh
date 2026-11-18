#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_data.csv
feature_A,feature_B,target,extra_col
1.2,3.4,5.0,ignore
2.1,1.1,3.2,ignore
,2.2,4.1,ignore
3.3,,5.5,ignore
4.1,5.5,9.6,ignore
0.5,0.1,0.6,ignore
1.0,1.0,2.0,ignore
2.0,2.0,4.0,ignore
3.0,3.0,6.0,ignore
4.0,4.0,8.0,ignore
5.0,5.0,10.0,ignore
EOF

    chmod -R 777 /home/user
