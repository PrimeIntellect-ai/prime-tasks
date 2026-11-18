import sys
import os
import json

# Ensure oracle uses its own unbugged version
sys.path.insert(0, '/opt/oracle')
from genomic_dsp import filter_signal

def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        data = json.loads(line)
        primer = data["primer"]
        seq = data["sequence"]
        sig = data["signal"]

        start = seq.find(primer)
        if start == -1:
            print("NO_MATCH")
        else:
            end = start + len(primer) - 1
            sliced = sig[start:end+1]
            filtered = filter_signal(sliced)
            print(", ".join([f"{x:.4f}" for x in filtered]))

if __name__ == "__main__":
    main()
