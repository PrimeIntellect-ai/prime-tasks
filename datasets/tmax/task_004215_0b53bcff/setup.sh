#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    python3 -c '
import os
import random

os.makedirs("/app/libfastcsv-0.9.3", exist_ok=True)

with open("/app/libfastcsv-0.9.3/Makefile", "w") as f:
    f.write("CC=gcc\n")
    f.write("CFLAGS=-O3 -Wall\n")
    f.write("libfastcsv.a: fastcsv.o\n")
    f.write("    ar rcs libfastcsv.a fastcsv.o\n")
    f.write("fastcsv.o: fastcsv.c fastcsv.h\n")
    f.write("    $(CC) $(CFLAGS) -c fastcsv.c\n")

with open("/app/libfastcsv-0.9.3/fastcsv.h", "w") as f:
    f.write("#ifndef FASTCSV_H\n")
    f.write("#define FASTCSV_H\n")
    f.write("typedef struct {\n")
    f.write("    char **fields;\n")
    f.write("    size_t num_fields;\n")
    f.write("} csv_row_t;\n")
    f.write("void parse_csv(const char *filename);\n")
    f.write("#endif\n")

with open("/app/libfastcsv-0.9.3/fastcsv.c", "w") as f:
    f.write("#include \"fastcsv.h\"\n")
    f.write("#include <stdio.h>\n")
    f.write("#include <stdlib.h>\n")
    f.write("void parse_csv(const char *filename) {\n")
    f.write("    // dummy implementation\n")
    f.write("}\n")

os.makedirs("/home/user", exist_ok=True)
os.makedirs("/app/eval_data/clean", exist_ok=True)
os.makedirs("/app/eval_data/evil", exist_ok=True)

def is_evil(alpha, beta):
    return 2.5 * alpha - 1.2 * beta > 10.0

with open("/home/user/train_sensor_data.csv", "w") as f:
    f.write("sensor_alpha,sensor_beta,is_anomaly\n")
    for _ in range(1000):
        alpha = random.uniform(-10, 10)
        beta = random.uniform(-10, 10)
        evil = 1 if is_evil(alpha, beta) else 0
        f.write(f"{alpha},{beta},{evil}\n")

for i in range(50):
    with open(f"/app/eval_data/clean/data_{i}.csv", "w") as f:
        f.write("sensor_alpha,sensor_beta\n")
        for _ in range(100):
            alpha = random.uniform(-10, 10)
            beta = random.uniform(-10, 10)
            if is_evil(alpha, beta):
                alpha -= 10 # Make it clean
            f.write(f"{alpha},{beta}\n")

for i in range(50):
    with open(f"/app/eval_data/evil/data_{i}.csv", "w") as f:
        f.write("sensor_alpha,sensor_beta\n")
        # Ensure at least one evil
        alpha = random.uniform(10, 20)
        beta = random.uniform(-10, 0)
        f.write(f"{alpha},{beta}\n")
        for _ in range(99):
            alpha = random.uniform(-10, 10)
            beta = random.uniform(-10, 10)
            f.write(f"{alpha},{beta}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
