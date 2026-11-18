#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest

    mkdir -p /app

    # Generate a dummy video fixture
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=10 -r 30 -y /app/dashboard_cam.mp4

    # Create the oracle binary
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <iomanip>

int main() {
    double count = 0, mean = 0, M2 = 0;
    double newValue;
    while (std::cin >> newValue) {
        count += 1;
        double delta = newValue - mean;
        mean += delta / count;
        double delta2 = newValue - mean;
        M2 += delta * delta2;
    }
    if (count < 2) {
        std::cout << std::fixed << std::setprecision(6) << 0.0 << std::endl;
    } else {
        std::cout << std::fixed << std::setprecision(6) << (M2 / (count - 1)) << std::endl;
    }
    return 0;
}
EOF
    g++ -O3 /tmp/oracle.cpp -o /app/oracle_stability_calc
    strip /app/oracle_stability_calc

    # Wrap pytest to ensure the test sees the exact environment variables without Apptainer's additions
    mv /usr/local/bin/pytest /usr/local/bin/pytest.real
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
export LD_LIBRARY_PATH=/dev/null
export CPLUS_INCLUDE_PATH=/dev/null
exec /usr/local/bin/pytest.real "$@"
EOF
    chmod +x /usr/local/bin/pytest

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
