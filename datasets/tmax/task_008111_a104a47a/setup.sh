#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential wget
pip3 install pytest numpy

useradd -m -s /bin/bash user || true

cd /home/user
wget http://www.fftw.org/fftw-3.3.10.tar.gz

python3 -c '
seq = "ACGTAACG" * 128
with open("sequence.txt", "w") as f:
    f.write(seq)
'

chmod -R 777 /home/user
