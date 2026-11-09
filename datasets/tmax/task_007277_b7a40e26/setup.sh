#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_equations.txt
Some standard math: MATH[[ 15 + 25 ]] and some more text.
Another one here: MATH[[ 10 * (2 + 3) ]]!
Duplicate fullwidth: MATH[[１０＊（２＋３）]]
Invalid expression syntax: MATH[[ 5 + ( 3 * 2 ]]
Ignore this MATH[[ 100 / 0 ]] division by zero.
Valid fullwidth math: MATH[[ １００ － ５０ ]]
Invalid characters: MATH[[ 10 * x + 5 ]]
Float division: MATH[[ 10 ／ 4 ]]
Multiple in one line: MATH[[ 3 * 3 ]] and MATH[[ ３＊３ ]] and MATH[[ 20 - 2 ]]
EOF

    chmod -R 777 /home/user
