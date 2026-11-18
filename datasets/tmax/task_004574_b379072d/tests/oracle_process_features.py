#!/usr/bin/env python3
import sys
import csv

def main():
    reader = csv.DictReader(sys.stdin)
    fieldnames = ['A', 'B', 'C', 'D', 'weighted_sum', 'interaction']
    writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
    writer.writeheader()
    for row in reader:
        a, b, c, d = float(row['A']), float(row['B']), float(row['C']), float(row['D'])
        w_sum = 3.5 * a + 0.2 * b + 1.8 * c + 4.0 * d
        inter = (a * b) - (c * d)
        row['weighted_sum'] = f"{w_sum:.4f}"
        row['interaction'] = f"{inter:.4f}"
        writer.writerow(row)

if __name__ == '__main__':
    main()
