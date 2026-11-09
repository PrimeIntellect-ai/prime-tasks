#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server redis-tools gcc
    pip3 install pytest redis

    mkdir -p /app/collector /app/malware

    # Create collector script with the bugs
    cat << 'EOF' > /app/collector/collector.py
import socket
import threading
import queue
import redis
import time
import sys

q = queue.Queue()
lock = threading.Lock()
stats = {'processed': 0, 'errors': 0}
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

def decode_payload(data):
    if not data:
        # Recursion bug: fails to return properly, causing infinite recursion
        return decode_payload(data)

    if data.startswith("layer:"):
        return decode_payload(data[6:])
    elif data.startswith("malformed:"):
        raise ValueError("Malformed payload")
    return data

def worker():
    while True:
        try:
            item = q.get(timeout=1)
        except queue.Empty:
            continue
        if item is None:
            break

        # Concurrency bug: lock acquired but not released on exception
        lock.acquire()
        try:
            decoded = decode_payload(item.decode('utf-8'))
            r.set(decoded, "1")
            stats['processed'] += 1
            lock.release()
        except Exception as e:
            stats['errors'] += 1
            # lock.release() is missing here, causing deadlock for other threads
        q.task_done()

def main():
    threads = []
    for _ in range(10):
        t = threading.Thread(target=worker)
        t.daemon = True
        t.start()
        threads.append(t)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('127.0.0.1', 5555))
    sock.settimeout(1.0)

    print("Collector listening on UDP 5555...")
    try:
        while True:
            try:
                data, addr = sock.recvfrom(1024)
                q.put(data)
            except socket.timeout:
                pass
    except KeyboardInterrupt:
        pass

if __name__ == '__main__':
    main()
EOF

    # Create malware simulator C code
    cat << 'EOF' > /app/malware/malware_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(5555);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    for (int i = 0; i < 10000; i++) {
        char buf[256];
        if (i % 1000 == 500) {
            strcpy(buf, "malformed:data");
        } else if (i % 1000 == 999) {
            strcpy(buf, "layer:");
        } else {
            sprintf(buf, "layer:layer:payload_%d", i);
        }
        sendto(sock, buf, strlen(buf), 0, (struct sockaddr*)&addr, sizeof(addr));
        usleep(50); // small delay to not overwhelm UDP buffer completely
    }
    close(sock);
    return 0;
}
EOF

    # Compile the malware simulator
    gcc -o /app/malware/malware_sim /app/malware/malware_sim.c

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/collector/collector.py > /dev/null 2>&1 &
echo $! > /app/collector.pid
EOF
    chmod +x /app/start_services.sh

    # Create run_malware.sh
    cat << 'EOF' > /app/run_malware.sh
#!/bin/bash
/app/malware/malware_sim
EOF
    chmod +x /app/run_malware.sh

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
