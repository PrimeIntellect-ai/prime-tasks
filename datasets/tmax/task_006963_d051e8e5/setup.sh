#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/etl

    cat << 'EOF' > /home/user/data/setup.sql
CREATE TABLE departments (
    id INTEGER PRIMARY KEY,
    name TEXT
);

CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT,
    manager_id INTEGER,
    dept_id INTEGER,
    salary INTEGER,
    hire_date DATE
);

INSERT INTO departments (id, name) VALUES (1, 'Engineering'), (2, 'Sales');

INSERT INTO employees (id, name, manager_id, dept_id, salary, hire_date) VALUES 
(1, 'Alice', NULL, 1, 150000, '2020-01-15'),
(2, 'Bob', 1, 1, 120000, '2020-03-01'),
(3, 'Charlie', 1, 1, 110000, '2020-05-20'),
(4, 'Diana', NULL, 2, 130000, '2019-11-10'),
(5, 'Evan', 4, 2, 90000, '2021-02-15'),
(6, 'Fiona', 2, 1, 95000, '2021-06-01');
EOF

    sqlite3 /home/user/data/company.db < /home/user/data/setup.sql

    cat << 'EOF' > /home/user/etl/pipeline.cpp
#include <iostream>
#include <sqlite3.h>
#include <fstream>

int main() {
    sqlite3* db;
    char* errMsg = 0;
    int rc = sqlite3_open("/home/user/data/company.db", &db);

    if (rc) {
        std::cerr << "Can't open database: " << sqlite3_errmsg(db) << std::endl;
        return 1;
    }

    // BUG: Implicit cross join below. Missing WHERE e.dept_id = d.id
    const char* staging_sql = "CREATE TABLE stg_emp_dept AS "
                              "SELECT e.id as emp_id, e.name as emp_name, d.name as dept_name, e.manager_id, e.salary, e.hire_date "
                              "FROM employees e, departments d;";

    rc = sqlite3_exec(db, staging_sql, 0, 0, &errMsg);
    if (rc != SQLITE_OK) {
        std::cerr << "SQL error: " << errMsg << std::endl;
        sqlite3_free(errMsg);
    }

    // TODO: Write analytical query with recursive CTE and window functions, then write to final_report.csv

    sqlite3_close(db);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
