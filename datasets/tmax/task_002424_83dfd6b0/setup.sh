#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest pandas networkx

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/entities.csv
id,name,type
E1,CorpAlpha,Company
E2,CorpBeta,Company
E3,FirstNational,Bank
E4,GlobalSupplier,Company
E5,RegionalSupplier,Company
E6,LocalSupplier,Company
E7,CorpGamma,Company
E8,InvestmentBank,Bank
E9,CorpDelta,Company
EOF

    cat << 'EOF' > /home/user/data/relationships.csv
source,target,relation_type,weight
E4,E1,SUPPLIES,1.0
E5,E1,SUPPLIES,1.0
E3,E1,LOAN_TO,1.0
E6,E2,SUPPLIES,1.0
E3,E2,LOAN_TO,1.0
E4,E7,SUPPLIES,1.0
E5,E7,SUPPLIES,1.0
E6,E7,SUPPLIES,1.0
E3,E7,LOAN_TO,1.0
E8,E7,LOAN_TO,1.0
E4,E9,SUPPLIES,1.0
E5,E9,SUPPLIES,1.0
E6,E9,SUPPLIES,1.0
E1,E9,SUPPLIES,1.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
