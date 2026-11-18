#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++ wget
    pip3 install pytest

    # Clone the vendored CSV parser
    git clone --depth 1 --branch 2.1.3 https://github.com/vincentlaucsb/csv-parser.git /app/csv-parser

    # Perturb the header file
    sed -i '1i #error "Please compile with C++98"\n#undef __cplusplus\n' /app/csv-parser/include/csv.hpp

    # Generate corpora
    python3 -c '
import os
os.makedirs("/home/user/corpora/clean", exist_ok=True)
os.makedirs("/home/user/corpora/evil", exist_ok=True)

for i in range(10):
    with open(f"/home/user/corpora/clean/clean_{i:02d}.csv", "w") as f:
        f.write("tx_id,waiting_for_tx_id\n")
        f.write(f"{i*10+1},{i*10+2}\n")
        f.write(f"{i*10+2},{i*10+3}\n")
        f.write(f"{i*10+3},{i*10+4}\n")

for i in range(10):
    with open(f"/home/user/corpora/evil/evil_{i:02d}.csv", "w") as f:
        f.write("tx_id,waiting_for_tx_id\n")
        f.write(f"{i*10+1},{i*10+2}\n")
        f.write(f"{i*10+2},{i*10+3}\n")
        f.write(f"{i*10+3},{i*10+1}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
