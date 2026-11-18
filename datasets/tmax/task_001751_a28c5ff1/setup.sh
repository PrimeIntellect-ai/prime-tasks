#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/legacy.cpp
#include <cstdlib>
#include <string>

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;
    std::string cmd = std::string("python3 -c \"import sys, pandas as pd, numpy as np; df=pd.read_csv(sys.argv[1]); df=df.set_index('timestamp'); df=df.interpolate(method='index'); df=df.bfill().ffill(); df=df.reset_index(); df=df.melt(id_vars=['timestamp'], var_name='sensor', value_name='value'); df['value']=df['value'].round(4); df=df.sort_values(by=['timestamp', 'sensor']); df=df.dropna(subset=['value']); df.to_csv(sys.argv[2], index=False)\" ") + argv[1] + " " + argv[2];
    return system(cmd.c_str());
}
EOF

    g++ -O3 /tmp/legacy.cpp -o /app/legacy_processor
    strip /app/legacy_processor
    rm /tmp/legacy.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
