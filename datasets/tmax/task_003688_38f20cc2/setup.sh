#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.tsv
id	text_input	model_score
1	Hello World!	0.85
2	Missing score	
3	NA	0.5
4	Bad score	1.5
5	Negative score	-0.1
6	This is a test...	0.99
7		0.2
8	Valid text.	0.0
9	Another valid text!	1.0
10	NaN	0.4
11	   Too much   space   	0.50
12	Not_A_Number	abc
EOF

    chmod -R 777 /home/user
