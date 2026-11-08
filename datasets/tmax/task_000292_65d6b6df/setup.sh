#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ make git
    pip3 install pytest Pillow

    # Generate the specs image
    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), 'TOLERANCE=0.000001', fill=(0, 0, 0))
d.text((10, 80), 'LISTEN_PORT=8888', fill=(0, 0, 0))
img.save('/app/specs.png')
"

    # Setup git repository
    mkdir -p /app/math_server
    cd /app/math_server
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > Makefile
all: server
server: main.o math_utils.o
	g++ -o server main.o math_utils.o
main.o: main.cpp
	g++ -c main.cpp
math_utils.o: math_utils.cpp
	g++ -c math_utils.cpp
clean:
	rm -f *.o server
EOF

    cat << 'EOF' > math_utils.h
#ifndef MATH_UTILS_H
#define MATH_UTILS_H
double f(double x);
double df(double x);
double find_root(double x0, double tolerance);
#endif
EOF

    cat << 'EOF' > math_utils.cpp
#include "math_utils.h"
#include <cmath>

double f(double x) {
    return x * x * x - 2 * x - 5;
}

double df(double x) {
    return 3 * x * x - 2;
}

double find_root(double x0, double tolerance) {
    double x = x0;
    while (std::abs(f(x)) > tolerance) {
        x = x - f(x) / df(x);
    }
    return x;
}
EOF

    cat << 'EOF' > main.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>
#include <iomanip>
#include "math_utils.h"

int main() {
    int port = 8080; // AGENT MUST CHANGE THIS TO 8888 based on image
    double tolerance = 1e-3; // AGENT MUST CHANGE THIS TO 1e-6 based on image

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);
        double x0 = std::stod(buffer);

        double root = find_root(x0, tolerance);

        char response[256];
        snprintf(response, sizeof(response), "%.5f\n", root);
        send(new_socket, response, strlen(response), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    git add .
    git commit -m "Initial commit: working root finder"

    # Introduce mathematical regression (convergence failure)
    sed -i 's/x = x - f(x) \/ df(x);/x = x + f(x) \/ df(x);/g' math_utils.cpp
    git add math_utils.cpp
    git commit -m "Optimize root finding algorithm"

    # Introduce linker error
    sed -i 's/g++ -o server main.o math_utils.o/g++ -o server main.o/g' Makefile
    git add Makefile
    git commit -m "Update Makefile"

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /app
    chmod -R 777 /home/user
