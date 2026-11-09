#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/raw_reviews.csv
review_id,timestamp,rating,review_text,metadata
A1B2C3D4E5,2023-01-01T12:00:00Z,5,Great app!,{"device": "ios", "theme": "dark"}
F6G7H8I9J0,2023-01-02T12:00:00Z,4,Good but buggy.,{"device": "android", "error": "E\u00X1 code"}
K1L2M3N4O5,2023-01-03,6,Amazing,{"device": "web"}
SHORT,2023-01-04,3,Meh,{"device": "ios"}
P6Q7R8S9T0,2023-01-05,2,Terrible,{"theme": "light"}
U1V2W3X4Y5,2023-01-06,1,Worst,{device: "web"}
A1B2C3D4E6,2023-01-01T12:00:00Z,5,Excellent app!,{"device": "ios", "theme": "light"}
F6G7H8I9J1,2023-01-02T12:00:00Z,3,Okay.,{"device": "android", "error": "E\u12ZZ"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
