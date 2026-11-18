#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Compile the oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/netcost.cpp
#include <iostream>
#include <string>
int main() {
    std::string input;
    std::getline(std::cin, input);
    long long cost = 0;
    for (size_t i = 0; i < input.length(); ++i) {
        cost += (int)input[i];
    }
    std::cout << cost << std::endl;
    return 0;
}
EOF
    g++ -O2 /opt/oracle/netcost.cpp -o /opt/oracle/netcost-oracle

    # Create the vendored package
    mkdir -p /app/netcost-1.2.0
    cat << 'EOF' > /app/netcost-1.2.0/processor.cpp
#include <iostream>
#include <string>
int main() {
    std::string input;
    std::getline(std::cin, input);
    long long cost = 0;
    // DELIBERATE BUG: -1
    for (size_t i = 0; i < input.length() - 1; ++i) {
        cost += (int)input[i];
    }
    std::cout << cost << std::endl;
    return 0;
}
EOF
    cat << 'EOF' > /app/netcost-1.2.0/Makefile
all:
	g++ -O2 processor.cpp -o netcost
EOF

    # Create initial directories and pipeline script
    mkdir -p /home/user/pipeline
    mkdir -p /home/user/reports
    mkdir -p /home/user/bin
    mkdir -p /tmp/qemu-vms
    echo "example_log_data" > /tmp/qemu-vms/log1.txt

    cat << 'EOF' > /home/user/pipeline/run_cost.sh
#!/bin/bash
# Runs in restricted environment (no PATH)

# Bug 1: Relies on PATH
TOOL="netcost"

# Bug 2: Relative output path
OUTFILE="reports/cost.out"

cat /home/user/vm-logs/log1.txt | $TOOL > $OUTFILE
EOF
    chmod +x /home/user/pipeline/run_cost.sh

    chown -R user:user /home/user/pipeline /home/user/reports /home/user/bin
    chmod -R 777 /home/user
