#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/feedback.csv
id,category,comment
1,Electronics,"The screen is amazing. Rating: 4.5/5"
2,Electronics,"Terrible battery. Score: 3/10."
3,Home,"Very cozy. 4/5 stars."
4,Home,"Melted in the wash. 0/5."
5,Toys,"Kids love it! Rating: 9/10"
6,Toys,"Dangerous edges. Score: 1/10."
7,Electronics,"No score given here."
8,Home,"Impossible score. 12/10."
9,Toys,"Div by zero. 5/0."
10,Kitchen,"Perfect. 10/10."
11,Kitchen,"Negative score. -1/5."
12,Kitchen,"Float denominator. 3.5/5.0."
EOF

chmod -R 777 /home/user
