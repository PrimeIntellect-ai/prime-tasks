#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
id,text
1,"Data Science requires statistical thinking and data intuition."
2,"Artificial Intelligence."
3,"12345 67890!@#$%"
4,"zzzzzzzzzz"
5,"abcdefghijklmnopqrstuvwxyz"
6,"A quick brown fox jumps over the lazy dog."
EOF

    cat << 'EOF' > /home/user/weights.csv
char,weight
a,0.5
b,-0.1
c,0.2
d,-0.3
e,0.8
f,0.0
g,-0.2
h,0.1
i,0.4
j,-0.5
k,0.0
l,0.3
m,-0.1
n,0.2
o,0.0
p,-0.4
q,0.9
r,0.1
s,0.5
t,0.3
u,-0.2
v,0.1
w,-0.1
x,0.0
y,-0.3
z,-0.9
EOF

    chmod -R 777 /home/user
