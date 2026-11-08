#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ ffmpeg curl wget
    pip3 install pytest

    mkdir -p /home/user/vision_math
    mkdir -p /app

    # Generate test video
    ffmpeg -f lavfi -i "color=black:s=320x240:d=2" -vf "drawbox=x='50+t*20':y='50+t*10':w=20:h=20:color=white:t=fill" -c:v libx264 -pix_fmt yuv420p /app/trajectory_test.mp4

    # Download httplib.h
    curl -sL https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h -o /home/user/vision_math/httplib.h

    # Create buggy server.cpp
    cat << 'EOF' > /home/user/vision_math/server.cpp
#include "httplib.h"
#include <iostream>
#include <thread>
#include <vector>
#include <cmath>
#include <cstdio>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

double x = 0, y = 0;
double sum_x = 0, sum_y = 0;
double sum_sq_x = 0, sum_sq_y = 0;
int n = 0;
double stddev_x = 0, stddev_y = 0;

void process_video() {
    FILE* pipe = popen("ffmpeg -i /app/trajectory_test.mp4 -f image2pipe -vcodec rawvideo -pix_fmt gray - 2>/dev/null", "r");
    if (!pipe) return;
    unsigned char frame[320*240];
    while (fread(frame, 1, 320*240, pipe) == 320*240) {
        double cx = 0, cy = 0;
        int count = 0;
        for (int i=0; i<240; i++) {
            for (int j=0; j<320; j++) {
                if (frame[i*320+j] > 200) {
                    cx += j; cy += i; count++;
                }
            }
        }
        if (count > 0) {
            cx /= count; cy /= count;
            x = cx; y = cy;
            n++;
            sum_x += x; sum_y += y;
            sum_sq_x += x*x; sum_sq_y += y*y;
            // Naive variance formula prone to catastrophic cancellation
            stddev_x = sqrt(sum_sq_x/n - (sum_x/n)*(sum_x/n));
            stddev_y = sqrt(sum_sq_y/n - (sum_y/n)*(sum_y/n));
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(30));
    }
    pclose(pipe);
}

void tcp_server() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8081);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);
    while (true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        double data[4] = {x, y, stddev_x, stddev_y};
        send(new_socket, data, 32, 0);
        close(new_socket);
    }
}

int main() {
    std::thread t1(process_video);
    std::thread t2(tcp_server);

    httplib::Server svr;
    svr.Get("/latest", [](const httplib::Request &, httplib::Response &res) {
        char buf[256];
        sprintf(buf, "{\"x\": %f, \"y\": %f, \"stddev_x\": %f, \"stddev_y\": %f}", x, y, stddev_x, stddev_y);
        res.set_content(buf, "application/json");
    });
    svr.listen("127.0.0.1", 8080);

    t1.join();
    t2.join();
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
