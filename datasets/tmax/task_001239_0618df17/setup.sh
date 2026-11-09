#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/products.csv
id,name,category,price,description
P001,Widget A,Tools,$12.50,A high quality widget for your tools.
P002,Widget B,Tools,$15.00,A decent widget for tools and hardware.
P003,Gadget A,Electronics,$45.99,Electronic gadget with high quality screen.
P004,Gadget B,Electronics,invalid,A cheap electronic gadget.
P005,Widget C,Tools,$10.00,High quality widget tools.
P006,Thingamajig,Hardware,$5.25,hardware tools and miscellaneous items.
P007,Super Widget,Tools,$20.00,A high quality widget for your tools.
EOF

    chmod -R 777 /home/user
