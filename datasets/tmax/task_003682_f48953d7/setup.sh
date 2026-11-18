#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make
    pip3 install pytest

    mkdir -p /home/user/sim_project/libs
    cd /home/user/sim_project

    cat << 'EOF' > dummy_v1.c
double compute_step(double current) { return current * 1.05; }
EOF

    cat << 'EOF' > dummy_v2.c
double compute_step_v2(double current) { return current * 1.05; }
EOF

    gcc -shared -o libs/libsimmath_v1.so -fPIC dummy_v1.c
    gcc -shared -o libs/libsimmath_v2.so -fPIC dummy_v2.c
    rm dummy_v1.c dummy_v2.c

    cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -Wall -Wextra -O2
LDFLAGS = -L./libs -lsimmath_v1 -Wl,-rpath=./libs

all: sim

sim: simulate.cpp
	$(CXX) $(CXXFLAGS) simulate.cpp -o sim $(LDFLAGS)

clean:
	rm -f sim output.csv
EOF

    cat << 'EOF' > simulate.cpp
#include <iostream>
#include <fstream>
#include <iomanip>

extern "C" {
    double compute_step_v2(double current);
}

int main() {
    std::ofstream out("output.csv");
    out << "iteration,value\n";

    double val = 1.0;
    for(int i = 1; i <= 100; ++i) {
        // PRECISION BUG: casting to float before passing to function, and intermediate float storage
        float temp = (float)val;
        val = compute_step_v2(temp);

        out << i << "," << std::fixed << std::setprecision(6) << val << "\n";
    }

    out.close();
    return 0;
}
EOF

    cat << 'EOF' > gen_baseline.cpp
#include <iostream>
#include <fstream>
#include <iomanip>

int main() {
    std::ofstream out("baseline.csv");
    out << "iteration,value\n";

    double val = 1.0;
    for(int i = 1; i <= 100; ++i) {
        val = val * 1.05;
        out << i << "," << std::fixed << std::setprecision(6) << val << "\n";
    }

    out.close();
    return 0;
}
EOF
    g++ gen_baseline.cpp -o gen_baseline
    ./gen_baseline
    rm gen_baseline gen_baseline.cpp

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
