#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    sqlite3 backups.db <<EOF
CREATE TABLE nodes (id TEXT PRIMARY KEY);
CREATE TABLE edges (source TEXT, target TEXT, weight INTEGER);
CREATE INDEX idx_edges_bad ON edges(source);

INSERT INTO nodes (id) VALUES ('Start'), ('A'), ('B'), ('C'), ('D'), ('Recovery');
INSERT INTO edges (source, target, weight) VALUES 
('Start', 'A', 5),
('Start', 'B', 2),
('B', 'A', 1),
('A', 'C', 2),
('B', 'D', 6),
('C', 'Recovery', 3),
('D', 'Recovery', 1);
EOF

    cat << 'EOF' > recovery.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

#define MAX_NODES 100
#define INF 999999

typedef struct {
    char id[32];
    int dist;
    char prev[32];
    int visited;
} NodeState;

NodeState states[MAX_NODES];
int node_count = 0;

int get_node_index(const char* id) {
    for (int i = 0; i < node_count; i++) {
        if (strcmp(states[i].id, id) == 0) return i;
    }
    strcpy(states[node_count].id, id);
    states[node_count].dist = INF;
    states[node_count].prev[0] = '\0';
    states[node_count].visited = 0;
    return node_count++;
}

// TODO: Implement this function using parameterized queries
// It should query the 'edges' table for all rows where source = current_node
// For each edge, find the target node index and update its distance if a shorter path is found.
void process_neighbors(sqlite3* db, const char* current_node, int current_dist) {
    sqlite3_stmt *stmt;
    const char *sql = "SELECT target, weight FROM edges WHERE source = ?";

    // YOUR CODE HERE:
    // 1. Prepare statement
    // 2. Bind current_node to the parameter
    // 3. Loop over sqlite3_step
    // 4. Inside the loop:
    //      const char* target = (const char*)sqlite3_column_text(stmt, 0);
    //      int weight = sqlite3_column_int(stmt, 1);
    //      int target_idx = get_node_index(target);
    //      if (current_dist + weight < states[target_idx].dist) {
    //          states[target_idx].dist = current_dist + weight;
    //          strcpy(states[target_idx].prev, current_node);
    //      }
    // 5. Finalize statement
}

int main(int argc, char** argv) {
    if (argc != 3) {
        printf("Usage: %s <start> <end>\n", argv[0]);
        return 1;
    }
    const char* start_node = argv[1];
    const char* end_node = argv[2];

    sqlite3 *db;
    if (sqlite3_open("backups.db", &db) != SQLITE_OK) {
        return 1;
    }

    int start_idx = get_node_index(start_node);
    states[start_idx].dist = 0;

    for (int i = 0; i < MAX_NODES; i++) {
        int min_dist = INF;
        int u = -1;
        for (int j = 0; j < node_count; j++) {
            if (!states[j].visited && states[j].dist < min_dist) {
                min_dist = states[j].dist;
                u = j;
            }
        }
        if (u == -1) break;
        states[u].visited = 1;
        process_neighbors(db, states[u].id, states[u].dist);
    }

    int end_idx = get_node_index(end_node);
    if (states[end_idx].dist == INF) {
        printf("No path found\n");
    } else {
        char path[1024] = "";
        char curr[32];
        strcpy(curr, end_node);
        while (curr[0] != '\0') {
            char temp[1024];
            if (path[0] == '\0') {
                sprintf(temp, "%s", curr);
            } else {
                sprintf(temp, "%s->%s", curr, path);
            }
            strcpy(path, temp);

            int c_idx = get_node_index(curr);
            strcpy(curr, states[c_idx].prev);
        }
        printf("%s\n", path);
    }

    sqlite3_close(db);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
