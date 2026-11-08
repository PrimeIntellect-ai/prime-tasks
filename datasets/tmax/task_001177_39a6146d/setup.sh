#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/components.csv
id,name,type
P-01,SuperWidget,product
A-01,WidgetCore,assembly
A-02,WidgetShell,assembly
A-03,CoreProcessor,assembly
R-01,Steel,raw
R-02,Plastic,raw
R-03,Silicon,raw
R-04,Copper,raw
EOF

    cat << 'EOF' > /home/user/bom.csv
parent_id,child_id,qty
P-01,A-01,2
P-01,A-02,1
A-01,A-03,1
A-01,R-01,3
A-02,R-02,5
A-02,R-01,1
A-03,R-03,4
A-03,R-04,2
EOF

    chmod -R 777 /home/user
