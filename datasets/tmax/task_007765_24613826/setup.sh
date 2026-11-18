#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Create daemon_logs.txt
    cat << 'EOF' > /home/user/daemon_logs.txt
[INFO] Connection from 192.168.1.10 - Latency: 12ms
[INFO] Connection from 10.0.0.5 - Latency: 15ms
[INFO] Connection from 192.168.1.10 - Latency: 11ms
[WARN] Connection from 172.16.0.42 - Latency: 850ms
[INFO] Connection from 10.0.0.5 - Latency: 14ms
[INFO] Connection from 192.168.1.10 - Latency: 10ms
[WARN] Connection from 172.16.0.42 - Latency: 910ms
[INFO] Connection from 10.0.0.5 - Latency: 16ms
EOF

    # 2. Create traffic_dump.txt (simulated hex dump of network traffic)
    cat << 'EOF' > /home/user/traffic_dump.txt
00000000  45 00 00 3c 1c 46 40 00  40 06 b1 e6 c0 a8 01 0a  |E..<..F@.@......|
00000010  0a 00 00 05 04 d2 00 50  00 00 00 00 00 00 00 00  |.......P........|
00000020  a0 02 72 10 3f d0 00 00  02 04 05 b4 04 02 08 0a  |..r.?...........|
00000030  48 45 4c 4c 4f 5f 53 59  53 54 45 4d 00 00 00 00  |HELLO_SYSTEM....|

00000040  45 00 00 3c 1c 47 40 00  40 06 b1 e6 ac 10 00 2a  |E..<..G@.@.....*|
00000050  0a 00 00 05 04 d2 00 50  00 00 00 00 00 00 00 00  |.......P........|
00000060  a0 02 72 10 3f d0 00 00  02 04 05 b4 04 02 08 0a  |..r.?...........|
00000070  43 4d 44 5f 56 4f 52 54  45 58 5f 38 38 32 31 00  |CMD_VORTEX_8821.|
EOF

    # 3. Create the C++ source, compile it, and remove the source
    cat << 'EOF' > /home/user/network_daemon.cpp
#include <iostream>
#include <string>

// Normal function
void process_connection() {
    std::cout << "Processing normal connection..." << std::endl;
}

// Hidden function for the anomalous payload
void execute_cmd_vortex_8821_routine() {
    std::cout << "Executing hidden diagnostics routine..." << std::endl;
}

int main(int argc, char** argv) {
    if (argc > 1) {
        std::string cmd = argv[1];
        if (cmd == "CMD_VORTEX_8821") {
            execute_cmd_vortex_8821_routine();
        } else {
            process_connection();
        }
    }
    return 0;
}
EOF

    g++ -O2 -o /home/user/network_daemon /home/user/network_daemon.cpp
    rm /home/user/network_daemon.cpp
    chmod +x /home/user/network_daemon

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
