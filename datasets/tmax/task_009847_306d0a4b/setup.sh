#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/math_texts.csv
id,text
1,linear algebra is a branch of mathematics concerning linear equations
2,mathematics is the science that deals with the logic of shape quantity and arrangement
3,calculus is the mathematical study of continuous change
4,statistics is the discipline that concerns the collection organization analysis interpretation and presentation of data
5,topology is concerned with the properties of a geometric object that are preserved under continuous deformations
6,geometry is a branch of mathematics concerned with properties of space that are related with distance shape size and relative position of figures
7,number theory is a branch of pure mathematics devoted primarily to the study of the integers and integer valued functions
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
