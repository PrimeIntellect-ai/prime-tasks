#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Node.js
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    # Create workspace
    mkdir -p /home/user/math-addon/src

    # Create package.json
    cat << 'EOF' > /home/user/math-addon/package.json
{
  "name": "math-addon",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "node test.js"
  },
  "dependencies": {
    "ffi-napi": "^4.0.3",
    "ref-napi": "^3.0.3"
  },
  "devDependencies": {
    "fast-check": "github:not-a-real-repo/fast-check-broken"
  }
}
EOF

    # Create src/Makefile
    cat << 'EOF' > /home/user/math-addon/src/Makefile
all: libmath.so

libmath.so: math.o
	g++ -o libmath.so math.o

math.o: math.cpp
	g++ -c math.cpp

clean:
	rm -f *.o *.so
EOF

    # Create src/math.cpp
    cat << 'EOF' > /home/user/math-addon/src/math.cpp
#include <stdint.h>

extern "C" {
    uint64_t fast_gcd(uint64_t a, uint64_t b) {
        if (a == 0) return b;
        if (b == 0) return a;

        while (b != 0) {
            uint64_t temp = b;
            // BUG: b = b % a instead of a % b
            b = b % a; 
            a = temp;
        }
        return a;
    }
}
EOF

    # Create test.js
    cat << 'EOF' > /home/user/math-addon/test.js
const ffi = require('ffi-napi');
const fc = require('fast-check');
const path = require('path');

const libPath = path.join(__dirname, 'src', 'libmath.so');

const mathLib = ffi.Library(libPath, {
  'fast_gcd': [ 'uint64', [ 'uint64', 'uint64' ] ]
});

function gcd_js(a, b) {
  if (a === 0n) return b;
  if (b === 0n) return a;
  while (b !== 0n) {
    let temp = b;
    b = a % b;
    a = temp;
  }
  return a;
}

try {
  fc.assert(
    fc.property(fc.maxSafeNat(), fc.maxSafeNat(), (a, b) => {
      const expected = gcd_js(BigInt(a), BigInt(b));
      const result = mathLib.fast_gcd(a, b);
      return BigInt(result) === expected;
    }),
    { numRuns: 1000 }
  );
  console.log("All property tests passed!");
} catch (e) {
  console.error(e);
  process.exit(1);
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/math-addon
    chmod -R 777 /home/user
