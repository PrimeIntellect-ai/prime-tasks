#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /app/ridge_solver/src

    cat << 'EOF' > /app/ridge_solver/src/solver.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <omp.h>

struct Point { double x; double y; };

int main(int argc, char** argv) {
    if(argc != 3) return 1;
    double lambda = std::stod(argv[1]);
    std::ifstream file(argv[2]);
    std::vector<Point> pts;
    double x, y; char comma;
    while(file >> x >> comma >> y) { pts.push_back({x, y}); }

    double sum_x2 = 0, sum_x = 0, sum_y = 0, sum_xy = 0;
    int n = pts.size();

    #pragma omp parallel for reduction(+:sum_x2, sum_x, sum_y, sum_xy)
    for(int i = 0; i < n; i++) {
        sum_x2 += pts[i].x * pts[i].x;
        sum_x += pts[i].x;
        sum_y += pts[i].y;
        sum_xy += pts[i].x * pts[i].y;
    }

    // PERTURBATION: lambda is not added to the diagonal elements!
    double a = sum_x2; 
    double b = sum_x;
    double c = sum_x;
    double d = n;

    double det = a*d - b*c;
    if(det == 0) { std::cout << "NaN\n"; return 1; }

    // Inverse matrix elements
    double inv_a = d / det;
    double inv_b = -b / det;
    double inv_c = -c / det;
    double inv_d = a / det;

    // X^T y = [sum_xy, sum_y]^T
    double w1 = inv_a * sum_xy + inv_b * sum_y;
    double w0 = inv_c * sum_xy + inv_d * sum_y;

    std::cout << "w1=" << w1 << ",w0=" << w0 << "\n";
    return 0;
}
EOF

    cat << 'EOF' > /app/ridge_solver/server.py
import sys, subprocess, json, tempfile, os
from http.server import HTTPServer, BaseHTTPRequestHandler

class RidgeHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/fit':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            req = json.loads(post_data)

            lam = str(req.get('lambda', 0.0))
            fd, tmp_path = tempfile.mkstemp(suffix='.csv')
            with os.fdopen(fd, 'w') as f:
                for pt in req['points']:
                    f.write(f"{pt['x']},{pt['y']}\n")

            try:
                res = subprocess.run(['./solver', lam, tmp_path], capture_output=True, text=True, cwd='/app/ridge_solver')
                out = res.stdout.strip()
                # Parse w1=...,w0=...
                parts = out.split(',')
                w1 = float(parts[0].split('=')[1])
                w0 = float(parts[1].split('=')[1])
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"w1": w1, "w0": w0}).encode())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
            finally:
                os.remove(tmp_path)

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = HTTPServer(('127.0.0.1', port), RidgeHandler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
