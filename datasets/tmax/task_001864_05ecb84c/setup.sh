#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest numpy pandas

    # Create user
    useradd -m -s /bin/bash user || true

    # Create fastcsv library
    mkdir -p /app/fastcsv-1.0
    cat << 'EOF' > /app/fastcsv-1.0/fastcsv.h
#ifndef FASTCSV_H
#define FASTCSV_H

#define MAX_COLUMNS 3

typedef struct {
    char *columns[MAX_COLUMNS];
    int column_count;
} CSVRow;

int parse_csv_line(char *line, CSVRow *row);

#endif
EOF

    cat << 'EOF' > /app/fastcsv-1.0/fastcsv.c
#include <string.h>
#include "fastcsv.h"

int parse_csv_line(char *line, CSVRow *row) {
    row->column_count = 0;
    char *token = strtok(line, ",\n\r");
    while (token != NULL) {
        if (row->column_count < MAX_COLUMNS) {
            row->columns[row->column_count] = token;
            row->column_count++;
        }
        token = strtok(NULL, ",\n\r");
    }
    return row->column_count;
}
EOF

    cat << 'EOF' > /app/fastcsv-1.0/Makefile
CC=gcc
CFLAGS=-Wall -fPIC
AR=ar

all: libfastcsv.a

libfastcsv.a: fastcsv.o
	$(AR) rcs $@ $^

fastcsv.o: fastcsv.c fastcsv.h
	$(CC) $(CFLAGS) -c fastcsv.c

clean:
	rm -f *.o *.a
EOF

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

os.makedirs("/home/user/data", exist_ok=True)
np.random.seed(123)
n = 50000
amounts = np.random.lognormal(mean=3.0, sigma=1.0, size=n)

df = pd.DataFrame({
    'id': np.arange(1, n+1),
    'timestamp': pd.date_range("2023-01-01", periods=n, freq="min"),
    'user_id': np.random.randint(1000, 5000, size=n),
    'amount': amounts,
    'category': np.random.choice(['A', 'B', 'C'], size=n)
})
df.to_csv("/home/user/data/sales.csv", index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app/fastcsv-1.0
