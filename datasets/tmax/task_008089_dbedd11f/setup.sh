#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential
    pip3 install pytest

    mkdir -p /home/user/heat_solver
    cd /home/user/heat_solver

    # Create the configuration file
    cat << 'EOF' > grid_config.txt
nx=20
ny=20
tol=0.001
max_iter=5000
EOF

    # Initialize git and commit the config file
    git init
    git config user.name "Previous Dev"
    git config user.email "dev@example.com"
    git add grid_config.txt
    git commit -m "Add initial grid configuration"

    # Delete the config file and commit the deletion
    rm grid_config.txt
    git add -u
    git commit -m "Oops, removing config by mistake"

    # Create solver.h
    cat << 'EOF' > solver.h
#ifndef SOLVER_H
#define SOLVER_H

int solve(int nx, int ny, double tol, int max_iter, double* grid);

#endif
EOF

    # Create solver.cpp (contains the convergence bug: max_error is not reset inside the loop)
    cat << 'EOF' > solver.cpp
#include "solver.h"
#include <cmath>
#include <iostream>

int solve(int nx, int ny, double tol, int max_iter, double* grid) {
    double* next_grid = new double[nx * ny];
    for(int i = 0; i < nx * ny; ++i) next_grid[i] = grid[i];

    double max_error = 0.0; // BUG: Should be reset to 0 inside the while/for loop

    int iter = 0;
    for (; iter < max_iter; ++iter) {
        // max_error = 0.0; // Missing!

        for (int y = 1; y < ny - 1; ++y) {
            for (int x = 1; x < nx - 1; ++x) {
                double val = 0.25 * (grid[(y-1)*nx + x] + grid[(y+1)*nx + x] + 
                                     grid[y*nx + x - 1] + grid[y*nx + x + 1]);
                next_grid[y*nx + x] = val;

                double err = std::abs(val - grid[y*nx + x]);
                if (err > max_error) {
                    max_error = err;
                }
            }
        }

        for(int i = 0; i < nx * ny; ++i) {
            grid[i] = next_grid[i];
        }

        if (max_error < tol) {
            break;
        }
    }

    delete[] next_grid;
    return iter;
}
EOF

    # Create main.cpp
    cat << 'EOF' > main.cpp
#include "solver.h"
#include <iostream>
#include <fstream>
#include <string>

int main() {
    std::ifstream infile("grid_config.txt");
    if (!infile) {
        std::cerr << "Error: grid_config.txt missing!" << std::endl;
        return 1;
    }

    int nx = 0, ny = 0, max_iter = 0;
    double tol = 0.0;
    std::string key;
    while (std::getline(infile, key, '=')) {
        double val;
        infile >> val;
        if (key == "nx" || key == "\nnx") nx = val;
        else if (key == "ny" || key == "\nny") ny = val;
        else if (key == "tol" || key == "\ntol") tol = val;
        else if (key == "max_iter" || key == "\nmax_iter") max_iter = val;
    }

    if (nx <= 0 || ny <= 0) return 1;

    double* grid = new double[nx * ny]();
    // Boundary conditions
    for (int x = 0; x < nx; ++x) {
        grid[x] = 100.0; // Top wall
    }

    int iters = solve(nx, ny, tol, max_iter, grid);

    std::cout << "Converged in " << iters << " iterations\n";

    delete[] grid;
    return 0;
}
EOF

    # Create Makefile with environment bug (uses gcc instead of g++, won't link stdlibc++)
    cat << 'EOF' > Makefile
CXX = gcc
CXXFLAGS = -Wall -O2

heat_sim: main.o solver.o
	$(CXX) $(CXXFLAGS) -o heat_sim main.o solver.o

main.o: main.cpp solver.h
	$(CXX) $(CXXFLAGS) -c main.cpp

solver.o: solver.cpp solver.h
	$(CXX) $(CXXFLAGS) -c solver.cpp

clean:
	rm -f *.o heat_sim
EOF

    git add main.cpp solver.cpp solver.h Makefile
    git commit -m "Add source files and Makefile"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
