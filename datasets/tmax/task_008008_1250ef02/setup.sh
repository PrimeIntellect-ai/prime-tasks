#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tzdata psmisc
    pip3 install pytest

    mkdir -p /home/user/src
    mkdir -p /home/user/bin
    mkdir -p /home/user/config
    mkdir -p /home/user/run
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/config/daemon.conf
TARGET_TIME=1700000000
EOF

    cat << 'EOF' > /home/user/config/daemon.env
TZ=Pacific/Honolulu
EOF

    cat << 'EOF' > /home/user/src/daemon.cpp
#include <iostream>
#include <fstream>
#include <string>

int main() {
    // Missing config reading
    // Missing PID writing
    // Missing correct time formatting
    std::ofstream out("output.log");
    out << "Broken" << std::endl;
    return 1;
}
EOF

    cat << 'EOF' > /home/user/bin/service_manager.sh
#!/bin/bash
COMMAND=$1

if [ "$COMMAND" == "start" ]; then
    /home/user/bin/daemon
elif [ "$COMMAND" == "stop" ]; then
    killall daemon
fi
EOF

    chmod +x /home/user/bin/service_manager.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
