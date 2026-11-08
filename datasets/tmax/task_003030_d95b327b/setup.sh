#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip coreutils gawk sed
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user

cat << 'EOF' > /home/user/mutation_rates.txt
1.234
0.892
NaN
1.056
1.112
0.985
NaN
0.745
1.301
0.888
0.912
1.405
1.011
NaN
1.115
0.955
1.205
0.835
1.002
1.099
0.876
NaN
1.155
1.023
0.965
1.123
0.887
1.034
0.992
1.250
EOF

chmod -R 777 /home/user
