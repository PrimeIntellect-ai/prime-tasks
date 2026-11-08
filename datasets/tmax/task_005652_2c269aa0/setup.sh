#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the SQLite database and populate it
    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
CREATE TABLE access_logs (id INTEGER PRIMARY KEY, employee_id INTEGER, resource TEXT, status TEXT, timestamp DATETIME);

INSERT INTO employees VALUES (1, 'Alice', 'Engineering');
INSERT INTO employees VALUES (2, 'Bob', 'HR');
INSERT INTO employees VALUES (3, 'Charlie', 'IT');
INSERT INTO employees VALUES (4, 'Diana', 'Finance');

INSERT INTO access_logs VALUES (1, 1, 'Vault', 'DENIED', '2023-10-01 10:00:00');
INSERT INTO access_logs VALUES (2, 2, 'ServerA', 'GRANTED', '2023-10-01 10:05:00');
INSERT INTO access_logs VALUES (3, 3, 'Firewall', 'DENIED', '2023-10-02 11:00:00');
INSERT INTO access_logs VALUES (4, 4, 'PayrollDB', 'DENIED', '2023-10-03 09:30:00');
INSERT INTO access_logs VALUES (5, 1, 'Vault', 'DENIED', '2023-10-04 14:00:00');
INSERT INTO access_logs VALUES (6, 2, 'PayrollDB', 'DENIED', '2023-10-05 08:15:00');
INSERT INTO access_logs VALUES (7, 3, 'Router1', 'GRANTED', '2023-10-05 09:00:00');
INSERT INTO access_logs VALUES (8, 4, 'Vault', 'DENIED', '2023-10-06 16:45:00');
INSERT INTO access_logs VALUES (9, 1, 'ServerB', 'DENIED', '2023-10-07 10:20:00');
INSERT INTO access_logs VALUES (10, 2, 'ServerA', 'DENIED', '2023-10-08 11:11:00');
INSERT INTO access_logs VALUES (11, 3, 'CoreSwitch', 'DENIED', '2023-10-09 12:00:00');
INSERT INTO access_logs VALUES (12, 1, 'Vault', 'DENIED', '2023-10-10 13:30:00');
INSERT INTO access_logs VALUES (13, 2, 'PayrollDB', 'DENIED', '2023-10-11 14:45:00');
INSERT INTO access_logs VALUES (14, 4, 'ServerA', 'DENIED', '2023-10-12 15:50:00');
INSERT INTO access_logs VALUES (15, 3, 'Firewall', 'DENIED', '2023-10-13 16:00:00');
EOF

    # Create the buggy C++ file
    cat << 'EOF' > /home/user/extractor.cpp
#include <iostream>
#include <fstream>
#include <sqlite3.h>
#include <string>

static int callback(void* data, int argc, char** argv, char** azColName) {
    std::ofstream* outFile = static_cast<std::ofstream*>(data);
    for (int i = 0; i < argc; i++) {
        *outFile << (argv[i] ? argv[i] : "NULL");
        if (i < argc - 1) *outFile << ",";
    }
    *outFile << "\n";
    return 0;
}

int main() {
    sqlite3* db;
    char* zErrMsg = 0;
    int rc;

    rc = sqlite3_open("/home/user/audit.db", &db);
    if (rc) {
        std::cerr << "Can't open database: " << sqlite3_errmsg(db) << "\n";
        return(0);
    }

    std::ofstream outFile("/home/user/audit_report.csv");
    outFile << "Name,Department,Resource,Timestamp\n";

    // BUG: Missing JOIN condition (implicit cross join)
    std::string sql = "SELECT employees.name, employees.department, access_logs.resource, access_logs.timestamp "
                      "FROM employees, access_logs "
                      "WHERE access_logs.status = 'DENIED' "
                      "ORDER BY access_logs.timestamp DESC LIMIT 10;";

    rc = sqlite3_exec(db, sql.c_str(), callback, &outFile, &zErrMsg);

    if (rc != SQLITE_OK) {
        std::cerr << "SQL error: " << zErrMsg << "\n";
        sqlite3_free(zErrMsg);
    }

    outFile.close();
    sqlite3_close(db);
    return 0;
}
EOF

    chmod -R 777 /home/user
