#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ strace tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/calc.cpp
#include <iostream>
#include <ctime>
#include <iomanip>

int main() {
    time_t t1 = 1622505600; // Tue Jun 01 2021 00:00:00 UTC
    time_t t2 = 1622511005;

    struct tm *tm1 = std::localtime(&t1);
    int hour1 = tm1->tm_hour;

    struct tm *tm2 = std::localtime(&t2);
    int hour2 = tm2->tm_hour;

    // BUG: Integer division causing precision loss
    double diff_hours = (t2 - t1) / 3600;

    std::cout << "Local Hour 1: " << hour1 << std::endl;
    std::cout << "Local Hour 2: " << hour2 << std::endl;
    std::cout << std::fixed << std::setprecision(4);
    std::cout << "Exact Diff: " << diff_hours << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/run_diag.sh
#!/bin/bash
g++ -o calc /home/user/calc.cpp
export TZ=Mars/Phobos
/home/user/calc
EOF

    chmod +x /home/user/run_diag.sh
    chmod -R 777 /home/user
