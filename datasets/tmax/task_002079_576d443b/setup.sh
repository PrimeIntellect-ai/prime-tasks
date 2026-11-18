#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import numpy as np

np.random.seed(42)
train = np.random.randn(8000, 5)
test = np.random.randn(2000, 5) + 10.0
data = np.vstack([train, test])
np.savetxt("/home/user/data.csv", data, delimiter=",", fmt="%.5f")

c_code = """
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ROWS 10000
#define COLS 5

int main() {
    FILE *fp = fopen("/home/user/data.csv", "r");
    if (!fp) {
        perror("Failed to open file");
        return 1;
    }

    double data[ROWS][COLS];
    double sums[COLS] = {0};
    char line[1024];
    int row = 0;

    while (fgets(line, sizeof(line), fp) && row < ROWS) {
        char *token = strtok(line, ",");
        for (int col = 0; col < COLS; col++) {
            if (token) {
                data[row][col] = atof(token);
                sums[col] += data[row][col];
                token = strtok(NULL, ",");
            }
        }
        row++;
    }
    fclose(fp);

    // BUG: Computes mean over the entire dataset
    double means[COLS];
    for (int col = 0; col < COLS; col++) {
        means[col] = sums[col] / ROWS;
    }

    FILE *out = fopen("/home/user/output.csv", "w");
    for (int r = 0; r < ROWS; r++) {
        for (int c = 0; c < COLS; c++) {
            fprintf(out, "%.5f%s", data[r][c] - means[c], (c == COLS - 1) ? "" : ",");
        }
        fprintf(out, "\\n");
    }
    fclose(out);
    return 0;
}
"""

with open("/home/user/etl_processor.c", "w") as f:
    f.write(c_code)

os.system("gcc -o /home/user/etl_processor /home/user/etl_processor.c")
'

    chmod -R 777 /home/user
