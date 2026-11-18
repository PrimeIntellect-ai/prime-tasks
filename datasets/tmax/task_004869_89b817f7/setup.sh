#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl coreutils gawk
    pip3 install pytest

    mkdir -p /home/user/network_tools
    cd /home/user/network_tools

    echo -n "dummy_pcap_data_stream_for_testing" > traffic.pcap

    cat << 'EOF' > analyzer.py
import argparse
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--secret-token', required=True)
    parser.add_argument('--data', required=True)
    args = parser.parse_args()

    with open(args.data, 'r') as f:
        content = f.read()

    with open('/home/user/network_tools/analysis.log', 'w') as f:
        f.write(f"TOKEN:{args.secret_token}\n")
        f.write(f"DATA_LENGTH:{len(content)}\n")

if __name__ == '__main__':
    main()
EOF

    sha384sum analyzer.py | awk '{print $1}' > checksum.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
