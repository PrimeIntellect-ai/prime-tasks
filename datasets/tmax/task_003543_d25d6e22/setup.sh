#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the vendored package directory
    mkdir -p /app/backup_service-1.0

    # Create Makefile
    cat << 'EOF' > /app/backup_service-1.0/Makefile
CC = gcc
CFLAGS = -Wall -Wextra -O2
LDFLAGS = 

backup_server: server.c
	$(CC) $(CFLAGS) -o backup_server server.c $(LDFLAGS)
EOF

    # Create server.c
    cat << 'EOF' > /app/backup_service-1.0/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sqlite3.h>

#define PORT 8080

void handle_client(int client_fd) {
    char buffer[1024];
    int bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
    if (bytes_read < 0) {
        close(client_fd);
        return;
    }
    buffer[bytes_read] = '\0';

    sqlite3 *db;
    if (sqlite3_open("/home/user/metadata.db", &db)) {
        close(client_fd);
        return;
    }

    const char *sql = "WITH RECURSIVE chain AS ( SELECT id, parent_id, size, backup_time FROM backups WHERE id = 5 UNION ALL SELECT b.id, b.parent_id, b.size, b.backup_time FROM backups b INNER JOIN chain c ON b.id = c.parent_id ) SELECT id, parent_id, size, SUM(size) OVER (ORDER BY backup_time) as cumulative_size FROM chain ORDER BY backup_time;";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        sqlite3_close(db);
        close(client_fd);
        return;
    }

    char json[2048] = "[";
    int first = 1;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (!first) strcat(json, ", ");
        char row[256];
        int id = sqlite3_column_int(stmt, 0);
        int parent_id = sqlite3_column_int(stmt, 1);
        int size = sqlite3_column_int(stmt, 2);
        int cum_size = sqlite3_column_int(stmt, 3);

        if (sqlite3_column_type(stmt, 1) == SQLITE_NULL) {
            sprintf(row, "{\"id\":%d, \"parent_id\":null, \"size\":%d, \"cumulative_size\":%d}", id, size, cum_size);
        } else {
            sprintf(row, "{\"id\":%d, \"parent_id\":%d, \"size\":%d, \"cumulative_size\":%d}", id, parent_id, size, cum_size);
        }
        strcat(json, row);
        first = 0;
    }
    strcat(json, "]");
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    char response[4096];
    sprintf(response, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n%s", json);

    close(client_fd);
    write(client_fd, response, strlen(response));
}

int main() {
    int server_fd, client_fd;
    struct sockaddr_in address;
    int opt = 1;
    socklen_t addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(PORT);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while (1) {
        if ((client_fd = accept(server_fd, (struct sockaddr *)&address, &addrlen)) < 0) exit(EXIT_FAILURE);
        handle_client(client_fd);
    }
    return 0;
}
EOF

    # Create and populate the SQLite database
    sqlite3 /home/user/metadata.db << 'EOF'
CREATE TABLE backups(id INTEGER PRIMARY KEY, parent_id INTEGER, size INTEGER, backup_time DATETIME);
INSERT INTO backups VALUES (1, NULL, 100, '2023-01-01 10:00:00');
INSERT INTO backups VALUES (3, 1, 50, '2023-01-02 10:00:00');
INSERT INTO backups VALUES (5, 3, 25, '2023-01-03 10:00:00');
CREATE INDEX idx_parent ON backups(parent_id);
EOF

    # Corrupt the index slightly by modifying the db file directly
    # A simple string replacement to mess up the index tree structure
    sed -i 's/idx_parent/idx_pXrXnt/g' /home/user/metadata.db || true

    chmod -R 777 /app
    chmod -R 777 /home/user
