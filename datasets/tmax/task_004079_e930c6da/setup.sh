#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget tar
    pip3 install pytest pandas

    mkdir -p /app/src /app/data /app/output /app/bin /opt/verifier

    # Download pcre2
    cd /app
    wget -q https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.gz
    tar -xzf pcre2-10.42.tar.gz
    rm pcre2-10.42.tar.gz

    # Introduce syntax error at line 185
    sed -i '185i int broken_var =' /app/pcre2-10.42/src/pcre2_compile.c

    # Create skeleton C program
    cat << 'EOF' > /app/src/loc_aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    // TODO: implement
    return 0;
}
EOF

    # Create data file
    cat << 'EOF' > /app/data/loc_updates.csv
timestamp,lang_code,text
2023-10-25T14:30:00Z,en-US,Hello
2023-10-25T14:30:00Z,en-US,Hello
2023-10-25T15:00:00Z,fr-FR,Bonjour
2023-10-25T16:00:00Z,en-US,World
2023-10-26T10:00:00Z,es-ES,Hola
EOF

    # Create golden summary
    cat << 'EOF' > /opt/verifier/golden_summary.csv
date,lang_code,update_count
2023-10-25,en-US,2
2023-10-25,fr-FR,1
2023-10-26,es-ES,1
EOF

    # Create verifier
    cat << 'EOF' > /opt/verifier/verify.py
import pandas as pd
import sys

try:
    df_agent = pd.read_csv('/app/output/summary.csv').set_index(['date', 'lang_code'])
    df_golden = pd.read_csv('/opt/verifier/golden_summary.csv').set_index(['date', 'lang_code'])

    merged = df_golden.join(df_agent, lsuffix='_gold', rsuffix='_agent', how='outer').fillna(0)
    total_expected = merged['update_count_gold'].sum()
    absolute_error = (merged['update_count_gold'] - merged['update_count_agent']).abs().sum()

    accuracy = 1.0 - (absolute_error / total_expected)
    print(f"Accuracy: {accuracy}")
    if accuracy >= 0.98:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f"Verification failed: {e}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /opt/verifier
