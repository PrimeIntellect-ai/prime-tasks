#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pandas numpy

    mkdir -p /app /home/user
    cd /app

    # Create the source code for the imputer binary
    cat << 'EOF' > imputer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input.csv> <output.csv>\n", argv[0]);
        return 1;
    }

    FILE *in = fopen(argv[1], "r");
    FILE *out = fopen(argv[2], "w");
    if (!in || !out) return 1;

    char line[256];
    // Read and write header
    if (fgets(line, sizeof(line), in)) {
        fputs(line, out);
    }

    double last_val = 50.0; // default starting impute value
    while (fgets(line, sizeof(line), in)) {
        char id[50], ts[50], val_str[50];
        // Parse the line manually to handle empty values
        int num_commas = 0;
        int i, len = strlen(line);
        int pos1 = -1, pos2 = -1;
        for(i=0; i<len; i++){
            if(line[i] == ','){
                if(num_commas == 0) pos1 = i;
                else if(num_commas == 1) pos2 = i;
                num_commas++;
            }
        }
        if (pos1 != -1 && pos2 != -1) {
            strncpy(id, line, pos1); id[pos1] = '\0';
            strncpy(ts, line + pos1 + 1, pos2 - pos1 - 1); ts[pos2 - pos1 - 1] = '\0';
            strcpy(val_str, line + pos2 + 1);

            // Remove newline
            val_str[strcspn(val_str, "\r\n")] = 0;

            double val;
            if (strlen(val_str) == 0 || strcmp(val_str, "NaN") == 0) {
                val = last_val; // Forward fill imputation
            } else {
                val = atof(val_str);
                if (val >= 0.0 && val <= 1000.0) {
                    last_val = val; // Only update last valid for non-outliers
                }
            }
            fprintf(out, "%s,%s,%.4f\n", id, ts, val);
        }
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF

    # Compile and strip to create the fixture
    gcc -O2 imputer.c -o imputer
    strip imputer
    rm imputer.c

    # Generate the dataset
    cat << 'EOF' > /home/user/generate_data.py
import random

random.seed(42)
with open("/home/user/sensor_data.csv", "w") as f:
    f.write("id,timestamp,value\n")
    for i in range(10000):
        # 5% missing, 5% outliers, 90% normal
        r = random.random()
        if r < 0.05:
            val = ""
        elif r < 0.10:
            val = random.choice([-50.0, 1500.0]) # Outliers
        else:
            val = random.gauss(50.0, 15.0)
        f.write(f"{i},2023-01-01T12:00:00Z,{val}\n")
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
