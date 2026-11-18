#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/sensor_project

cat << 'EOF' > /home/user/sensor_project/sensor_data.txt
100000.01
100000.05
100000.02
100000.08
100000.04
100000.09
100000.01
100000.03
100000.07
100000.06
EOF

cat << 'EOF' > /home/user/sensor_project/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <assert.h>

#define WINDOW 5

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <data_file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("Error opening file");
        return 1;
    }

    double window[WINDOW] = {0};
    int w_idx = 0;
    int count = 0;

    // Variables for naive variance
    float sum = 0;
    float sum_sq = 0;

    printf("Line,Value,MovingAvg,RunningVar\n");

    float val_f;
    while (fscanf(f, "%f", &val_f) == 1) {
        double val = (double)val_f;
        count++;

        window[w_idx % WINDOW] = val;
        w_idx++;

        double w_sum = 0;
        int limit = count < WINDOW ? count : WINDOW;

        // BUG 1: Off-by-one error (<= instead of <)
        for (int i = 0; i <= limit; i++) {
            w_sum += window[i % WINDOW];
        }
        double m_avg = w_sum / limit;

        // BUG 2: Naive formula and float precision -> catastrophic cancellation
        sum += val_f;
        sum_sq += val_f * val_f;

        float variance = 0;
        if (count > 1) {
            variance = (sum_sq - (sum * sum) / count) / (count - 1);
        }

        // Validate state
        assert(variance >= -0.001);

        printf("%d,%.2f,%.2f,%.6f\n", count, val, m_avg, variance);
    }
    fclose(f);
    return 0;
}
EOF

cat << 'EOF' > /home/user/sensor_project/run_pipeline.sh
#!/bin/bash
gcc -g -O0 processor.c -o processor -lm
./processor sensor_data.txt
EOF
chmod +x /home/user/sensor_project/run_pipeline.sh

cat << 'EOF' > /tmp/generate_truth.py
data = [
    100000.01,
    100000.05,
    100000.02,
    100000.08,
    100000.04,
    100000.09,
    100000.01,
    100000.03,
    100000.07,
    100000.06
]

window = []
mean = 0.0
M2 = 0.0

print("Line,Value,MovingAvg,RunningVar")
for i, val in enumerate(data):
    count = i + 1

    # Welford's algorithm for running variance
    delta = val - mean
    mean += delta / count
    delta2 = val - mean
    M2 += delta * delta2

    if count > 1:
        variance = M2 / (count - 1)
    else:
        variance = 0.0

    # Moving average
    window.append(val)
    if len(window) > 5:
        window.pop(0)

    m_avg = sum(window) / len(window)

    print(f"{count},{val:.2f},{m_avg:.2f},{variance:.6f}")
EOF

python3 /tmp/generate_truth.py > /home/user/sensor_project/expected_output.csv

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
