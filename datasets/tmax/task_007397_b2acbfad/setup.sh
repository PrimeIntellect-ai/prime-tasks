#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/polybuild/src /home/user/polybuild/tests

    cat << 'EOF' > /home/user/polybuild/build.poly
@target all
@deps app_bin & test_run
@lang Meta
@run echo "Build complete"

@target app_bin
@deps none
@lang C++
@run g++ src/app.cpp -o app

@target test_run
@deps app_bin
@lang Python
@run python3 tests/verify.py
EOF

    cat << 'EOF' > /home/user/polybuild/src/app.cpp
#include <iostream>
int main() {
    std::cout << "POLYBUILD_APP_OK" << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/polybuild/tests/verify.py
import subprocess
import sys

try:
    result = subprocess.run(['./app'], capture_output=True, text=True, check=True)
    if "POLYBUILD_APP_OK" in result.stdout:
        with open('/home/user/polybuild/build_success.log', 'w') as f:
            f.write("INTEGRATION_TEST_PASSED\n")
        print("Test passed.")
    else:
        print("Output mismatch.")
        sys.exit(1)
except Exception as e:
    print(f"Test failed: {e}")
    sys.exit(1)
EOF

    chmod -R 777 /home/user
