#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk bc
pip3 install pytest

mkdir -p /home/user/research_data

cat << 'EOF' > /home/user/research_data/dataset.csv
id,split,label,text
1,train,A,quantum mechanics superposition states particles quantum physics entanglement particle
2,train,A,entanglement theorem quantum states superpositions theorem mechanics states
3,train,B,cellular biology mitosis genetics cellular mutation protein biology
4,train,B,genetics protein synthesis biology cellular mitosis cellular mutation
5,train,A,quantum computing algorithms mechanics physics algorithms superposition
6,train,B,mitosis sequence biology genetics cellular protein
7,train,A,physics entanglement particle states quantum algorithms physics
8,train,B,mutation synthesis cellular biology mitosis genetics
101,test,?,cellular states quantum biology physics
102,test,?,mitosis cellular genetics synthesis protein
103,test,?,mechanics quantum physics algorithms superposition
104,test,?,biology sequence mutation protein quantum
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
