#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the input data file
    cat << 'EOF' > /home/user/data.csv
id,text
1,"Data science is great. Rust is fast."
2,"Vector and matrix math in rust!"
3,"No matching words here."
4,"DATA, data, ScIeNcE, vector vector!"
EOF

    # Set permissions
    chmod -R 777 /home/user
