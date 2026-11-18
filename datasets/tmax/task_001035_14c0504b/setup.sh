#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/lib-ts-window-0.5/include
    mkdir -p /app/lib-ts-window-0.5/src
    mkdir -p /app/lib-ts-window-0.5/lib

    # Create Makefile with the broken c++11 flag
    cat << 'EOF' > /app/lib-ts-window-0.5/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -Wall -Wextra -Iinclude
AR = ar
ARFLAGS = rcs

TARGET = lib/libtswindow.a
OBJS = src/tswindow.o

all: $(TARGET)

$(TARGET): $(OBJS)
	mkdir -p lib
	$(AR) $(ARFLAGS) $@ $^

src/%.o: src/%.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -rf src/*.o lib
EOF

    # Create header file
    cat << 'EOF' > /app/lib-ts-window-0.5/include/tswindow.h
#ifndef TSWINDOW_H
#define TSWINDOW_H

#include <string_view>
#include <vector>

namespace tswindow {
    struct Point3D {
        double x, y, z;
    };

    class RollingWindow {
    public:
        RollingWindow(size_t size);
        void add(Point3D p);
        Point3D get_centroid() const;
        size_t size() const;
        void print_status(std::string_view status) const;
    private:
        size_t max_size;
        std::vector<Point3D> points;
    };
}

#endif
EOF

    # Create source file
    cat << 'EOF' > /app/lib-ts-window-0.5/src/tswindow.cpp
#include "tswindow.h"
#include <iostream>

namespace tswindow {
    RollingWindow::RollingWindow(size_t size) : max_size(size) {}

    void RollingWindow::add(Point3D p) {
        if (points.size() >= max_size) {
            points.erase(points.begin());
        }
        points.push_back(p);
    }

    Point3D RollingWindow::get_centroid() const {
        if (points.empty()) return {0.0, 0.0, 0.0};
        double sum_x = 0, sum_y = 0, sum_z = 0;
        for (const auto& p : points) {
            sum_x += p.x;
            sum_y += p.y;
            sum_z += p.z;
        }
        double n = points.size();
        return {sum_x / n, sum_y / n, sum_z / n};
    }

    size_t RollingWindow::size() const {
        return points.size();
    }

    void RollingWindow::print_status(std::string_view status) const {
        std::cout << status << " Window size: " << points.size() << "\n";
    }
}
EOF

    # Create data directories
    mkdir -p /app/data/clean_corpus
    mkdir -p /app/data/evil_corpus

    # Create clean corpus
    cat << 'EOF' > /app/data/clean_corpus/clean_1.csv
timestamp,x,y,z
1,0.0,0.0,0.0
2,0.1,0.1,0.1
3,0.2,0.2,0.2
4,0.3,0.3,0.3
5,0.4,0.4,0.4
6,0.5,0.5,0.5
7,0.6,0.6,0.6
EOF

    # Create evil corpus
    cat << 'EOF' > /app/data/evil_corpus/evil_1.csv
timestamp,x,y,z
1,0.0,0.0,0.0
2,0.1,0.1,0.1
1,0.2,0.2,0.2
3,0.2,0.2,0.2
4,100.0,100.0,100.0
5,0.4,0.4,0.4
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
