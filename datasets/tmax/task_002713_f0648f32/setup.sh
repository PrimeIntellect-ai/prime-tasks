#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/raw
    mkdir -p /home/user/processed

    cat << 'EOF' > /home/user/raw/demographics.txt
uid|age|country
101|25|US
102|17|UK
103|bad|CA
104|40|FR
105|30|
106|22|DE
108|29|JP
109|35|AU
EOF

    cat << 'EOF' > /home/user/raw/reviews.txt
uid	review_text	score
101	This is Awesome!	5
101	Terrible.	2
104	Works well, but a bit pricey.	4
105	Good	5
106		4
107	Ghost user	5
108	100% PERFECT!!	5
109	Okay I guess	3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
