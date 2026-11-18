#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/graph_tools-1.0.0/bin

    cat << 'EOF' > /app/graph_tools-1.0.0/Makefile
install:
	mkdir -p /usr/local/bin
	cp bin/graph_tool /usr/local/bin/graph_tool
	chmod +x /usr/local/bin/graph_tool
	mkdir -p /usr/local/lib/graph_tools
	cp graph_fft.py /usr/local/lib/graph_tools/graph_fft.py
EOF

    cat << 'EOF' > /app/graph_tools-1.0.0/bin/graph_tool
#!/bin/bash
PYTHON_EXE=python2
$PYTHON_EXE /usr/local/lib/graph_tools/graph_fft.py "$@"
EOF
    chmod +x /app/graph_tools-1.0.0/bin/graph_tool

    cat << 'EOF' > /app/graph_tools-1.0.0/graph_fft.py
import sys
import argparse
import csv

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    args = parser.parse_args()

    val = 0.0
    count = 0
    with open(args.input, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            try:
                val += sum(float(x) for x in row)
                count += 1
            except ValueError:
                pass

    if count > 0:
        print(val / count * 1.5)
    else:
        print(0.0)

if __name__ == '__main__':
    main()
EOF

    mkdir -p /home/user/data
    python3 -c "
import random
random.seed(42)
with open('/home/user/data/signals.csv', 'w') as f:
    f.write('A,B,C\n')
    for _ in range(100):
        val = random.gauss(32.66, 13.08)
        f.write(f'{val},0,0\n')
"

    chmod -R 777 /home/user
    chmod -R 777 /app
