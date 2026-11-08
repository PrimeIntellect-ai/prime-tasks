#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        sqlite3 \
        libsqlite3-dev \
        g++ \
        nlohmann-json3-dev \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Create the audit policy image
    # We modify ImageMagick policy to allow text to image conversion if restricted
    sed -i 's/rights="none" pattern="LABEL"/rights="read | write" pattern="LABEL"/' /etc/ImageMagick-6/policy.xml || true
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"CONFIDENTIAL AUDIT MANDATE: You must trace financial pathways.\nIgnore noise: Minimum Transfer Amount is 500.\nMaximum Traversal Depth is 4 hops." /app/audit_policy.png

    # Create and populate the database
    sqlite3 /app/financials.db <<EOF
CREATE TABLE accounts (id INTEGER PRIMARY KEY, type TEXT);
CREATE TABLE transfers (source INTEGER, target INTEGER, amount REAL);

WITH RECURSIVE cnt(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM cnt WHERE x<1000)
INSERT INTO accounts SELECT x, 'standard' FROM cnt;

WITH RECURSIVE cnt(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM cnt WHERE x<3000)
INSERT INTO transfers 
SELECT 
  (abs(random()) % 1000) + 1,
  (abs(random()) % 1000) + 1,
  (abs(random()) % 1000) + 100
FROM cnt;

-- Create a corrupted index simulation (partial index that agent shouldn't use)
CREATE INDEX idx_transfers_source ON transfers(source) WHERE amount < 200; 
EOF

    # Create the oracle
    cat << 'EOF' > /app/oracle_audit.cpp
#include <iostream>
#include <vector>
#include <string>
#include <sqlite3.h>
#include <nlohmann/json.hpp>
#include <queue>
#include <set>
#include <algorithm>

using json = nlohmann::json;

int main(int argc, char* argv[]) {
    if (argc != 4) return 1;
    int start_node = std::stoi(argv[1]);
    int offset = std::stoi(argv[2]);
    int limit = std::stoi(argv[3]);

    sqlite3* db;
    if (sqlite3_open("/app/financials.db", &db) != SQLITE_OK) return 1;

    std::set<int> visited;
    std::queue<std::pair<int, int>> q;
    q.push({start_node, 0});
    visited.insert(start_node);

    std::vector<int> reachable;

    while (!q.empty()) {
        auto [curr, depth] = q.front();
        q.pop();

        if (depth >= 4) continue;

        std::string query = "SELECT target FROM transfers NOT INDEXED WHERE source = " + std::to_string(curr) + " AND amount >= 500;";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, query.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                int target = sqlite3_column_int(stmt, 0);
                if (visited.find(target) == visited.end()) {
                    visited.insert(target);
                    reachable.push_back(target);
                    q.push({target, depth + 1});
                }
            }
            sqlite3_finalize(stmt);
        }
    }
    sqlite3_close(db);

    std::sort(reachable.rbegin(), reachable.rend());

    json j;
    j["total_reachable"] = reachable.size();

    std::vector<int> paginated;
    for (size_t i = offset; i < offset + limit && i < reachable.size(); ++i) {
        paginated.push_back(reachable[i]);
    }
    j["paginated_results"] = paginated;

    std::cout << j.dump() << std::endl;
    return 0;
}
EOF

    g++ -O3 -std=c++17 /app/oracle_audit.cpp -o /app/oracle_audit -lsqlite3
    chmod +x /app/oracle_audit

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
