#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/linreg_ref.cpp
#include <iostream>
#include <queue>
#include <string>
#include <numeric>

using namespace std;

long long gcd(long long a, long long b) {
    while (b) {
        a %= b;
        swap(a, b);
    }
    return a;
}

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);

    queue<pair<long long, long long>> q;
    long long n = 0;
    long long sum_x = 0;
    long long sum_y = 0;
    long long sum_xx = 0;
    long long sum_xy = 0;

    string cmd;
    while (cin >> cmd) {
        if (cmd == "ADD") {
            long long x, y;
            cin >> x >> y;
            q.push({x, y});
            n++;
            sum_x += x;
            sum_y += y;
            sum_xx += x * x;
            sum_xy += x * y;
        } else if (cmd == "REMOVE_OLDEST") {
            if (q.empty()) {
                cout << "ERROR\n";
            } else {
                long long x = q.front().first;
                long long y = q.front().second;
                q.pop();
                n--;
                sum_x -= x;
                sum_y -= y;
                sum_xx -= x * x;
                sum_xy -= x * y;
            }
        } else if (cmd == "PREDICT") {
            long long x;
            cin >> x;
            if (n < 2) {
                cout << "ERROR\n";
                continue;
            }
            long long D = n * sum_xx - sum_x * sum_x;
            if (D == 0) {
                cout << "ERROR\n";
                continue;
            }
            long long N1 = n * sum_xy - sum_x * sum_y;
            long long num = sum_y * D + N1 * (n * x - sum_x);
            long long den = n * D;

            if (den < 0) {
                num = -num;
                den = -den;
            }
            long long g = gcd(abs(num), abs(den));
            num /= g;
            den /= g;
            if (den == 1) {
                cout << num << "\n";
            } else {
                cout << num << "/" << den << "\n";
            }
        }
    }
    return 0;
}
EOF

    g++ -O3 -o /app/linreg_ref /app/linreg_ref.cpp
    strip /app/linreg_ref
    rm /app/linreg_ref.cpp

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/linreg.py
import sys
class LinReg:
    def __init__(self):
        self.pts = []
    def add(self, x, y):
        self.pts.append((x,y))
    def remove_oldest(self):
        if self.pts: self.pts.pop(0)
        else: print("ERROR")
    def predict(self, x):
        print("ERROR")

l = LinReg()
for line in sys.stdin:
    parts = line.split()
    if not parts: continue
    if parts[0] == 'ADD': l.add(int(parts[1]), int(parts[2]))
    elif parts[0] == 'REMOVE_OLDEST': l.remove_oldest()
    elif parts[0] == 'PREDICT': l.predict(int(parts[1]))
EOF

    chmod -R 777 /home/user
