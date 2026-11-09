#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server g++ make libomp-dev curl
    pip3 install pytest flask redis

    mkdir -p /home/user/config
    mkdir -p /home/user/src/sim_engine
    mkdir -p /app/data/corpus/evil
    mkdir -p /app/data/corpus/clean
    mkdir -p /home/user/bin
    mkdir -p /home/user/data/latest

    cat << 'EOF' > /home/user/start_services.sh
#!/bin/bash
echo "Starting services..."
EOF
    chmod +x /home/user/start_services.sh

    cat << 'EOF' > /home/user/config/api.env
REDIS_HOST=wrong_host
REDIS_PORT=9999
EOF

    cat << 'EOF' > /home/user/config/worker.conf
queue_name=wrong_queue
EOF

    cat << 'EOF' > /home/user/src/sim_engine/main.cpp
#include <iostream>
int main() {
    std::cout << "Worker started" << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/sim_engine/ode_solver.cpp
// ODE Solver with reduction issue
EOF

    cat << 'EOF' > /home/user/src/sim_engine/Makefile
all: worker
worker: main.cpp ode_solver.cpp
	g++ -fopenmp main.cpp ode_solver.cpp -o worker
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
