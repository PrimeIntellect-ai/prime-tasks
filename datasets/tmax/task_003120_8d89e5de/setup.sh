#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/fast-udp-probe-1.0
    mkdir -p /app/router-sim

    cat << 'EOF' > /app/fast-udp-probe-1.0/probe.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/time.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <ip> <port>\n", argv[0]);
        return 1;
    }

    char *ip = argv[1];
    int port = atoi(argv[2]);

    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, ip, &addr.sin_addr);

    int packets = 10000;
    char dummy[64] = "test";

    struct timeval start, end;
    gettimeofday(&start, NULL);

    for (int i = 0; i < packets; i++) {
        sendto(sock, dummy, sizeof(dummy), 0, (struct sockaddr *)&addr, sizeof(addr));
        usleep(100000); // Perturbation
    }

    gettimeofday(&end, NULL);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_usec - start.tv_usec) / 1000000.0;
    double pps = packets / elapsed;

    printf("Throughput: %.2f pps\n", pps);

    close(sock);
    return 0;
}
EOF

    cat << 'EOF' > /app/fast-udp-probe-1.0/Makefile
fast-udp-probe: probe.c
	gcc -o fast-udp-probe probe.c
EOF

    cat << 'EOF' > /app/router-sim/start_endpoint.sh
#!/bin/bash
python3 -c "
import socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('127.0.0.1', 8080))
while True:
    data, addr = sock.recvfrom(1024)
" &
echo $! > /tmp/router_sim.pid
EOF
    chmod +x /app/router-sim/start_endpoint.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
