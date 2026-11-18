#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang g++ make imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"DEPLOYMENT SPECS\nPORT: 8080\nENDPOINT: /api/v1/compute\nTARGET_MS: 500" /app/deployment_spec.png

    mkdir -p /home/user/src/cpp /home/user/src/go

    cat << 'EOF' > /home/user/src/cpp/compute.h
#ifdef __cplusplus
extern "C" {
#endif
double process_array(const double* arr, int size);
#ifdef __cplusplus
}
#endif
EOF

    cat << 'EOF' > /home/user/src/cpp/compute.cpp
#include "compute.h"
#include <cmath>

double process_array(const double* arr, int size) {
    double sum = 0;
    // Bottleneck: artificial delay or highly inefficient loop
    for(int i=0; i<size; i++) {
        for(int j=0; j<100000; j++) { 
            sum += (arr[i] * 0.00001);
        }
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/src/cpp/Makefile
all: compute.o
	g++ -o libcompute.so compute.o

compute.o: compute.cpp
	g++ -c compute.cpp
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
