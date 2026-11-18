#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make sqlite3 libsqlite3-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/ticket_8832/logs
mkdir -p /home/user/ticket_8832/src
mkdir -p /home/user/ticket_8832/db

# Create SQLite DB
sqlite3 /home/user/ticket_8832/db/results.db "CREATE TABLE convergence_runs (id INTEGER PRIMARY KEY, input_value REAL, result_value REAL, status TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP);"
sqlite3 /home/user/ticket_8832/db/results.db "INSERT INTO convergence_runs (input_value, result_value, status) VALUES (10.0, 5.0, 'SUCCESS');"
sqlite3 /home/user/ticket_8832/db/results.db "INSERT INTO convergence_runs (input_value, result_value, status) VALUES (2500.0, -1.0, 'FAILED');"

# Create logs
cat << 'EOF' > /home/user/ticket_8832/logs/node_A.log
2023-10-27T10:00:05Z [INFO] Node A processing job_id=101 input_value=10.0
2023-10-27T10:00:07Z [INFO] Node A completed job_id=101 successfully.
2023-10-27T10:01:02Z [ERROR] Node A iteration overflow for job_id=104 input_value=2500.0
EOF

cat << 'EOF' > /home/user/ticket_8832/logs/node_B.log
2023-10-27T10:00:10Z [INFO] Node B processing job_id=102 input_value=15.5
2023-10-27T10:00:15Z [INFO] Node B completed job_id=102 successfully.
EOF

cat << 'EOF' > /home/user/ticket_8832/logs/node_C.log
2023-10-27T10:00:55Z [INFO] Node C processing job_id=103 input_value=42.0
2023-10-27T10:01:00Z [INFO] Node C completed job_id=103 successfully.
2023-10-27T10:00:58Z [INFO] Node A starting job_id=104 input_value=2500.0
EOF

# Create C++ Source code
cat << 'EOF' > /home/user/ticket_8832/src/optimizer.cpp
#include <iostream>
#include <cmath>
#include <sqlite3.h>
#include <string>

// Simulates the convergence engine
double optimize(double start_val) {
    float x = start_val; // BUG: Precision loss
    short iterations = 0; // BUG: Integer overflow (max 32767)
    float learning_rate = 0.0001f;

    while (iterations < 40000) { 
        float prev_x = x;
        x = x - learning_rate * (2 * x - 10); 
        if (std::abs(x - prev_x) < 1e-7) {
            break;
        }
        iterations++;
        if (iterations < 0) {
            std::cerr << "[ERROR] iteration overflow detected!" << std::endl;
            return -1.0;
        }
    }
    return x;
}

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <input_value>" << std::endl;
        return 1;
    }

    double input_value = std::stod(argv[1]);
    double result = optimize(input_value);

    sqlite3* db;
    if (sqlite3_open("/home/user/ticket_8832/db/results.db", &db)) {
        std::cerr << "Can't open database: " << sqlite3_errmsg(db) << std::endl;
        return 1;
    }

    std::string status = (result == -1.0) ? "FAILED" : "SUCCESS";
    std::string sql = "INSERT INTO convergence_runs (input_value, result_value, status) VALUES (" + 
                      std::to_string(input_value) + ", " + std::to_string(result) + ", '" + status + "');";

    char* errMsg = 0;
    if (sqlite3_exec(db, sql.c_str(), 0, 0, &errMsg) != SQLITE_OK) {
        std::cerr << "SQL error: " << errMsg << std::endl;
        sqlite3_free(errMsg);
    } else {
        std::cout << "Record inserted successfully. Result: " << result << std::endl;
    }
    sqlite3_close(db);
    return 0;
}
EOF

cat << 'EOF' > /home/user/ticket_8832/src/Makefile
optimizer_service: optimizer.cpp
	g++ -O2 -o optimizer_service optimizer.cpp -lsqlite3
EOF

chown -R user:user /home/user/ticket_8832
chmod -R 777 /home/user
