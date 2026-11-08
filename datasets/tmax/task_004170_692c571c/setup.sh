#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ patch build-essential
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/routes_base.conf
/api/v1/users USERS_SERVICE
/api/v1/auth AUTH_SERVICE
/api/v1/billing BILLING_SERVICE
/api/v1/orders ORDERS_SERVICE
/api/v1/products PRODUCTS_SERVICE
EOF

    cat << 'EOF' > /app/security_update.patch
--- routes_base.conf
+++ routes.conf
@@ -3,3 +3,4 @@
 /api/v1/billing BILLING_SERVICE
 /api/v1/orders ORDERS_SERVICE
 /api/v1/products PRODUCTS_SERVICE
+/api/v1/secure SECURE_SERVICE
EOF

    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <unordered_map>
#include <vector>
#include <fstream>
#include <sstream>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    unordered_map<string, string> routes;
    ifstream conf(argv[1]);
    string line;
    while (getline(conf, line)) {
        stringstream ss(line);
        string path, service;
        if (ss >> path >> service) {
            routes[path] = service;
        }
    }

    unordered_map<string, unordered_map<long long, int>> rate_limits;

    while (getline(cin, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        long long ts;
        string ip, method, path;
        // Format: [Timestamp] [IP_Address] [HTTP_Method] [URL_Path]
        if (ss >> ts >> ip >> method >> path) {
            long long window = ts;
            rate_limits[ip][window]++;
            if (rate_limits[ip][window] > 10) {
                cout << ip << " " << path << " -> DENIED_RATE_LIMIT\n";
            } else {
                string best_match = "";
                string target_service = "";
                for (auto const& pair : routes) {
                    if (path.find(pair.first) == 0) {
                        if (pair.first.length() > best_match.length()) {
                            best_match = pair.first;
                            target_service = pair.second;
                        }
                    }
                }
                if (best_match.empty()) {
                    cout << ip << " " << path << " -> DENIED_INVALID_ROUTE\n";
                } else {
                    cout << ip << " " << path << " -> ROUTED_TO_" << target_service << "\n";
                }
            }
        }
    }
    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/legacy_waf_oracle
    strip /app/legacy_waf_oracle
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
