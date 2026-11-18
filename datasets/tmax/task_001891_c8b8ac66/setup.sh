#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core g++ netcat-openbsd bc gawk
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the topology image
    mkdir -p /app
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -annotate +20+50 "Upstream socket: /tmp/metrics_backend.sock \n Timezone: Asia/Tokyo" \
        /app/topology.png

    # Create router.conf
    cat << 'EOF' > /home/user/router.conf
upstream backend { server unix:/tmp/wrong.sock; }
EOF

    # Create router_error.log
    cat << 'EOF' > /home/user/router_error.log
[error] 2023/10/01 10:00:00 502 Bad Gateway - connection refused
[info] 2023/10/01 10:01:00 200 OK
[error] 2023/10/01 10:02:00 502 Bad Gateway - socket not found
EOF

    # Create backend server.cpp
    mkdir -p /home/user/backend
    cat << 'EOF' > /home/user/backend/server.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstring>

// INTENTIONAL SLOWDOWN: pass by value, string concatenation in loop
std::string process_metric(std::string data) {
    std::string result = "";
    for(int i = 0; i < 1000; i++) {
        result = result + " "; 
    }
    return data + result;
}

int main() {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, "/tmp/wrong.sock"); // Needs to be changed to /tmp/metrics_backend.sock
    unlink(addr.sun_path);
    bind(fd, (struct sockaddr*)&addr, sizeof(addr));
    listen(fd, 5);
    while(true) {
        int client = accept(fd, NULL, NULL);
        char buf[1024];
        int len = read(client, buf, sizeof(buf));
        if (len > 0) {
            std::string processed = process_metric(std::string(buf, len));
            write(client, "OK", 2);
        }
        close(client);
    }
    return 0;
}
EOF

    # Create benchmark.sh
    cat << 'EOF' > /home/user/benchmark.sh
#!/bin/bash
# Connects to the socket defined in router.conf 10000 times and measures time
SOCK=$(grep -o 'unix:[^;]*' /home/user/router.conf | cut -d':' -f2)
if [ ! -S "$SOCK" ]; then
    echo "999.0" # Fail: socket doesn't exist
    exit 1
fi

START=$(date +%s.%N)
for i in {1..10000}; do
    echo "metric" | nc -U $SOCK > /dev/null
done
END=$(date +%s.%N)
echo "$END - $START" | bc
EOF
    chmod +x /home/user/benchmark.sh

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
