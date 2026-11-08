#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/measurements.csv
id,length,width,height,stated_volume
A1,10.0,5.0,2.0,100.0
A2,12.0,10.0,5.0,600.0
B1,7.5,4.0,2.0,62.0
B2,8.0,8.0,8.0,500.0
C1,15.0,2.0,2.0,60.5
C2,20.0,10.0,10.0,2000.0
EOF

    cat << 'EOF' > /home/user/metadata.csv
id,name,price_string
A1,Café,€12.50
A2,抹茶,¥1500.00
B1,Käse,€8.99
B2,سجادة,£45.00
C1,Crème,€15.25
C2,Té,£20.00
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
