#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make valgrind
    pip3 install pytest

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    cat << 'EOF' > filter.cpp
#include <iostream>

extern "C" {
    void moving_average(const double* input, double* output, int size, int window) {
        // MEMORY LEAK: temp is allocated but never freed
        double* temp = new double[size]; 

        for (int i = 0; i < size; ++i) {
            double sum = 0;
            int count = 0;
            for (int j = 0; j < window; ++j) {
                if (i - j >= 0) {
                    sum += input[i - j];
                    count++;
                }
            }
            output[i] = sum / count;
            temp[i] = output[i]; // Useless operation to use the buffer
        }
    }
}
EOF

    cat << 'EOF' > test_runner.cpp
#include <iostream>

extern "C" void moving_average(const double* input, double* output, int size, int window);

int main() {
    int size = 1000;
    double* input = new double[size];
    double* output = new double[size];

    for(int i=0; i<size; ++i) input[i] = i;

    moving_average(input, output, size, 5);

    delete[] input;
    delete[] output;
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all: libfilter.so test_runner

# BUG: Missing shared flag
libfilter.so: filter.o
	g++ -o libfilter.so filter.o

# BUG: Missing position independent flag
filter.o: filter.cpp
	g++ -c filter.cpp

test_runner: test_runner.cpp filter.o
	g++ -o test_runner test_runner.cpp filter.o

clean:
	rm -f *.o *.so test_runner
EOF

    cat << 'EOF' > benchmark.py
import ctypes
import time
import os

def python_moving_average(data, window):
    output = []
    for i in range(len(data)):
        sum_val = 0
        count = 0
        for j in range(window):
            if i - j >= 0:
                sum_val += data[i - j]
                count += 1
        output.append(sum_val / count)
    return output

if __name__ == "__main__":
    lib_path = os.path.join(os.path.dirname(__file__), "libfilter.so")
    if not os.path.exists(lib_path):
        print("Error: libfilter.so not found!")
        exit(1)

    lib = ctypes.CDLL(lib_path)

    # void moving_average(const double* input, double* output, int size, int window)
    lib.moving_average.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.POINTER(ctypes.c_double), ctypes.c_int, ctypes.c_int]
    lib.moving_average.restype = None

    size = 50000
    window = 50
    data = [float(i) for i in range(size)]

    InputArray = ctypes.c_double * size
    input_c = InputArray(*data)
    output_c = InputArray()

    # Benchmark C++
    start = time.time()
    lib.moving_average(input_c, output_c, size, window)
    cpp_time = time.time() - start

    # Benchmark Python
    start = time.time()
    python_moving_average(data, window)
    py_time = time.time() - start

    print(f"C++ Time: {cpp_time:.4f}s")
    print(f"Python Time: {py_time:.4f}s")
    print("Benchmark complete.")
EOF

    chmod +x benchmark.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
