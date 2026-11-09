#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make rustc cargo curl
    pip3 install pytest flask requests sympy

    # Create directories
    mkdir -p /home/user/legacy_math_api
    mkdir -p /app/bin
    mkdir -p /home/user/rust_backend/src
    mkdir -p /home/user/c_wrapper

    # 1. /home/user/legacy_math_api/app.py
    cat << 'EOF' > /home/user/legacy_math_api/app.py
import urllib2
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/evaluate', methods=['POST'])
def evaluate():
    try:
        data = request.get_json()
        expr = data['expression']
        x_val = data['x_value']
        print "starting evaluation for", expr
        # Dummy logic
        return jsonify({"result": 0.0})
    except Exception, e:
        return jsonify({"error": "Invalid expression"}), 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    # 2. /app/bin/core_evaluator_v1.bin
    cat << 'EOF' > /tmp/core.c
#include <stdio.h>
double evaluate_core(double coeffs[5], double x) {
    return coeffs[0] + coeffs[1]*x + coeffs[2]*x*x + coeffs[3]*x*x*x + coeffs[4]*x*x*x*x;
}
int main() {
    return 0;
}
EOF
    gcc -O2 /tmp/core.c -o /app/bin/core_evaluator_v1.bin
    strip /app/bin/core_evaluator_v1.bin
    rm /tmp/core.c

    # 3. /home/user/rust_backend/src/lib.rs
    cat << 'EOF' > /home/user/rust_backend/src/lib.rs
#[no_mangle]
pub extern "C" fn process_arrays(data: &mut [f64; 5], multiplier: f64) {
    let reference = &data[0];
    for i in 0..5 {
        data[i] = data[i] * multiplier + *reference; // Borrow checker error
    }
}
EOF

    cat << 'EOF' > /home/user/rust_backend/Cargo.toml
[package]
name = "mathcore_rust"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    # 4. /home/user/c_wrapper/Makefile
    cat << 'EOF' > /home/user/c_wrapper/Makefile
all: libmathcore.so

libmathcore.so: wrapper.o
	gcc -shared -o libmathcore.so wrapper.o -L../rust_backend/target/release -lmathcore_rust

wrapper.o: wrapper.c
	gcc -c -fPIC wrapper.c

clean:
	rm -f *.o *.so
EOF

    # 5. /home/user/c_wrapper/wrapper.c
    cat << 'EOF' > /home/user/c_wrapper/wrapper.c
#include <stdio.h>

extern void process_arrays(double* data, double multiplier);

double evaluate_core(double coeffs[5], double x) {
    process_arrays(coeffs, 1.0);
    return coeffs[0] + coeffs[1]*x + coeffs[2]*x*x + coeffs[3]*x*x*x + coeffs[4]*x*x*x*x;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
