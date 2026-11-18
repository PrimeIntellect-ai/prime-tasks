#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/solver.c
#include <stdio.h>
#include <stdlib.h>

int count = 0;

int abs_val(int x) { return x < 0 ? -x : x; }

int is_safe(int *board, int row, int col) {
    for (int i = 0; i < row; i++) {
        if (board[i] == col || abs_val(board[i] - col) == abs_val(i - row))
            return 0;
    }
    return 1;
}

void solve(int *board, int row, int n) {
    if (row == n) {
        count++;
        return;
    }
    for (int col = 0; col < n; col++) {
        if (is_safe(board, row, col)) {
            board[row] = col;
            solve(board, row + 1, n);
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    int n = atoi(argv[1]);

    // BUG 1: Off-by-one buffer allocation (should be n * sizeof(int))
    int *board = malloc((n - 1) * sizeof(int));

    solve(board, 0, n);
    printf("%d\n", count);

    // BUG 2: Memory leak (missing free)
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/backend.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/'):
            try:
                n = int(self.path.split('/')[-1])
                res = subprocess.check_output(['/home/user/app/solver', str(n)])
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(res)
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"Error")

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), RequestHandler)
    server.serve_forever()
EOF

    chown -R user:user /home/user/app
    chmod -R 777 /home/user
