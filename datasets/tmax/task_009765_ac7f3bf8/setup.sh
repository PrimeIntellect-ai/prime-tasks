#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.csv
id,review_text,rating,timestamp
1,"This is a great product",5,1620000000
2,"Bad",1,1620000010
3,"I really loved using this item every day",5,1620000020
4,"Not what I expected at all",2,1620000030
5,"Okay but could be significantly better in quality",3,1620000040
6,"It broke after two days of use",1,1620000050
7,"Absolutely fantastic experience from start to finish",5,1620000060
8,"Meh",3,1620000070
9,"The quality is acceptable for the price point",4,1620000080
10,"Will never ever buy this awful product again",1,1620000090
EOF
    chmod 644 /home/user/raw_data.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
