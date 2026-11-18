#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user

    # Generate the FASTA data
    python3 -c '
seq = "AGCT" * 25000
with open("/home/user/data.fasta", "w") as f:
    f.write(">seq1\n")
    for i in range(0, len(seq), 80):
        f.write(seq[i:i+80] + "\n")
'

    # Create parser.c
    cat << 'EOF' > /home/user/parser.c
#include <stdio.h>
int main(int argc, char** argv) {
    if(argc != 3) return 1;
    FILE* in = fopen(argv[1], "r");
    FILE* out = fopen(argv[2], "wb");
    char line[2048];
    while(fgets(line, sizeof(line), in)) {
        if(line[0] == '>') continue;
        for(int i=0; line[i]!='\0' && line[i]!='\n'; i++) {
            float val = 0.0f;
            if(line[i]=='A' || line[i]=='G') val = 1.0f;
            else if(line[i]=='C' || line[i]=='T') val = -1.0f;
            fwrite(&val, sizeof(float), 1, out);
        }
    }
    fclose(in); fclose(out);
    return 0;
}
EOF

    # Create original analyze.py
    cat << 'EOF' > /home/user/analyze.py
import numpy as np

def parse_fasta(file_path):
    vals = []
    with open(file_path, 'r') as f:
        for line in f:
            if line.startswith('>'): continue
            for char in line.strip():
                if char in ('A', 'G'): vals.append(1.0)
                elif char in ('C', 'T'): vals.append(-1.0)
                else: vals.append(0.0)
    return np.array(vals, dtype=np.float32)

def main():
    arr = parse_fasta('/home/user/data.fasta')
    fft_res = np.fft.fft(arr)
    mags = np.abs(fft_res)
    mags[0] = 0 # ignore DC
    peak_idx = int(np.argmax(mags))
    peak_mag = float(mags[peak_idx])
    print(f"Index: {peak_idx}, Mag: {peak_mag:.1f}")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
