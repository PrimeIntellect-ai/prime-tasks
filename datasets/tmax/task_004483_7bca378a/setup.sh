#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/pr_review
    cd /home/user/pr_review

    cat << 'EOF' > fast_sum.s
.global fast_sum
.type fast_sum, @function
fast_sum:
    # a in %edi, b in %esi, c in %edx
    movl %edi, %eax
    addl %esi, %eax
    addl %edx, %eax
    ret
EOF

    cat << 'EOF' > magic_square.cpp
#include <iostream>
#include <vector>

extern "C" int fast_sum(int a, int b, int c);

struct Square {
    int grid[3][3];
    bool used[10];

    Square() {
        for(int i=0; i<3; ++i)
            for(int j=0; j<3; ++j)
                grid[i][j] = 0;
        for(int i=0; i<10; ++i) used[i] = false;
    }

    bool is_valid() {
        // Check rows
        for(int i=0; i<3; ++i)
            if(fast_sum(grid[i][0], grid[i][1], grid[i][2]) != 15) return false;

        // Check columns
        for(int j=0; j<3; ++j)
            if(fast_sum(grid[0][j], grid[1][j], grid[2][j]) != 15) return false;

        // Check main diagonal
        if(fast_sum(grid[0][0], grid[1][1], grid[2][2]) != 15) return false;

        // BUG: Missing anti-diagonal check!

        return true;
    }

    void print() {
        for(int i=0; i<3; ++i) {
            std::cout << grid[i][0] << " " << grid[i][1] << " " << grid[i][2] << "\n";
        }
    }
};

bool solve(Square& sq, int row, int col) {
    if (row == 3) {
        return sq.is_valid();
    }

    int next_row = (col == 2) ? row + 1 : row;
    int next_col = (col == 2) ? 0 : col + 1;

    for (int num = 1; num <= 9; ++num) {
        if (!sq.used[num]) {
            sq.grid[row][col] = num;
            sq.used[num] = true;

            if (solve(sq, next_row, next_col)) return true;

            sq.grid[row][col] = 0;
            sq.used[num] = false;
        }
    }
    return false;
}

int main() {
    Square sq;
    if (solve(sq, 0, 0)) {
        sq.print();
    } else {
        std::cout << "No solution\n";
    }
    return 0;
}
EOF

    cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -O2 -Wall

all: magic_square

magic_square: magic_square.cpp
	$(CXX) $(CXXFLAGS) -o magic_square magic_square.cpp

clean:
	rm -f magic_square
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
