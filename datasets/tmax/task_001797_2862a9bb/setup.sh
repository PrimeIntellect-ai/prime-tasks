#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install required system packages
apt-get install -y protobuf-c-compiler libprotobuf-c-dev gcc make patch

# Create project directory
mkdir -p /home/user/project
cd /home/user/project

# Create message.proto
cat << 'EOF' > message.proto
syntax = "proto3";
message MathResult {
  int32 value = 1;
}
EOF

# Create compute.h
cat << 'EOF' > compute.h
#ifndef COMPUTE_H
#define COMPUTE_H
int compute_sum_of_squares(int n);
#endif
EOF

# Create compute.c
cat << 'EOF' > compute.c
#include "compute.h"
int compute_sum_of_squares(int n) {
    int sum = 0;
    for (int i = 1; i <= n; i++) {
        sum += i * i;
    }
    return sum;
}
EOF

# Create main.c
cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include "compute.h"
#include "message.pb-c.h"

int main() {
    MathResult msg = MATH_RESULT__INIT;
    msg.value = compute_sum_of_squares(10);
    printf("Result: %d\n", msg.value);
    return 0;
}
EOF

# Create Makefile with a circular dependency
cat << 'EOF' > Makefile
app: main.o compute.o message.pb-c.o
	gcc -o app main.o compute.o message.pb-c.o -lprotobuf-c

main.o: main.c compute.h compute.o
	gcc -c main.c

compute.o: compute.c compute.h main.o
	gcc -c compute.c

message.pb-c.o: message.pb-c.c message.pb-c.h
	gcc -c message.pb-c.c
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chown -R user:user /home/user/project
chmod -R 777 /home/user
