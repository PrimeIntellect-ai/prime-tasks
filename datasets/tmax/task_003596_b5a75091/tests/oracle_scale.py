import sys
import csv
import math

def scale(input_path, output_path):
    with open(input_path, 'r') as fin, open(output_path, 'w') as fout:
        reader = csv.reader(fin)
        for row in reader:
            if not row: continue
            label = float(row[-1])
            feats = [float(x) for x in row[:-1]]

            sq_sum = sum(x*x for x in feats)
            norm = math.sqrt(sq_sum)

            fout.write(f"{label:.6f}")
            for i, val in enumerate(feats):
                if norm > 0:
                    val = val / norm
                formatted_val = f"{val:.6f}"
                if formatted_val != "0.000000":
                    fout.write(f" {i+1}:{formatted_val}")
            fout.write("\n")

if __name__ == "__main__":
    scale(sys.argv[1], sys.argv[2])
