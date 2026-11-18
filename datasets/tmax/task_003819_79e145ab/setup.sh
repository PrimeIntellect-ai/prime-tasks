#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate instructions.wav
    espeak -w /app/instructions.wav "Write a Python script to fix our data leakage. It will take an integer N as the first command line argument. Read a list of floats from standard input, one per line. Missing values are represented exactly as minus nine hundred and ninety nine point zero. Step one: Calculate the mean and sample standard deviation using ONLY the valid, non-missing values within the first N rows. Step two: Replace all missing values in the ENTIRE dataset with this computed train-set mean. Step three: Clip all values in the ENTIRE dataset so they are bounded within exactly two point five standard deviations of the train-set mean. Step four: Standardize the entire dataset by subtracting the train-set mean and dividing by the train-set sample standard deviation. Finally, print each transformed value on a new line, rounded to four decimal places. If the standard deviation is zero, output zero for all standardized values."

    # Create oracle_transform
    cat << 'EOF' > /app/oracle_transform
#!/usr/bin/env python3
import sys
import math

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    try:
        N = int(sys.argv[1])
    except ValueError:
        sys.exit(1)

    data = []
    for line in sys.stdin:
        line = line.strip()
        if line:
            data.append(float(line))

    train_data = data[:N]
    valid_train = [x for x in train_data if x != -999.0]

    if not valid_train:
        mean = 0.0
        std = 0.0
    else:
        mean = sum(valid_train) / len(valid_train)
        if len(valid_train) > 1:
            variance = sum((x - mean) ** 2 for x in valid_train) / (len(valid_train) - 1)
            std = math.sqrt(variance)
        else:
            std = 0.0

    for x in data:
        if x == -999.0:
            val = mean
        else:
            val = x

        if std > 0:
            lower = mean - 2.5 * std
            upper = mean + 2.5 * std
            if val < lower:
                val = lower
            elif val > upper:
                val = upper

            val = (val - mean) / std
        else:
            val = 0.0

        print(f"{val:.4f}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_transform

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
