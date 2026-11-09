#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ gawk
pip3 install pytest

mkdir -p /home/user

# Generate data.txt (100 random floats)
gawk 'BEGIN {srand(42); for(i=0;i<100;i++) printf "%.4f\n", rand()*100}' > /home/user/data.txt

# Generate indices.txt (10000 lines, 100 ints per line, 0-99)
gawk 'BEGIN {
    srand(1337);
    for(i=0; i<10000; i++) {
        for(j=0; j<100; j++) {
            printf "%d", int(rand()*100);
            if(j<99) printf " ";
        }
        printf "\n";
    }
}' > /home/user/indices.txt

chmod 644 /home/user/data.txt /home/user/indices.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
