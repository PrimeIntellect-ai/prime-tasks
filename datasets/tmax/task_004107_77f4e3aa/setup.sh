#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server g++ make
    pip3 install pytest flask redis

    mkdir -p /home/user/app
    mkdir -p /opt/oracle

    cat << 'EOF' > /home/user/app/solver.cpp
#include <iostream>
#include <vector>
#include <queue>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

using namespace std;

void handle_client(int client_socket) {
    unsigned int N, M;
    if (recv(client_socket, &N, sizeof(N), 0) <= 0) return;
    if (recv(client_socket, &M, sizeof(M), 0) <= 0) return;

    int in_degree[100]; // Bug 1: fixed size buffer, heap overflow for jobs > 100
    memset(in_degree, 0, sizeof(in_degree));
    vector<vector<int>> adj(N);

    for (unsigned int i = 0; i < M; ++i) {
        unsigned int u, v;
        recv(client_socket, &u, sizeof(u), 0);
        recv(client_socket, &v, sizeof(v), 0);
        adj[u].push_back(v);
        in_degree[v]++;
    }

    bool visited[N]; // Bug 2: uninitialized read
    priority_queue<int, vector<int>, greater<int>> pq;

    for (unsigned int i = 0; i < N; ++i) {
        if (in_degree[i] == 0) {
            pq.push(i);
        }
    }

    vector<unsigned int> order;
    while (!pq.empty()) {
        int u = pq.top();
        pq.pop();
        order.push_back(u);
        for (int v : adj[u]) {
            in_degree[v]--;
            if (in_degree[v] == 0) {
                pq.push(v);
            }
        }
    }

    unsigned int K = order.size();
    send(client_socket, &K, sizeof(K), 0);
    send(client_socket, order.data(), K * sizeof(unsigned int), 0);
    close(client_socket);
}

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8081);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while (true) {
        int client_socket = accept(server_fd, nullptr, nullptr);
        handle_client(client_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/gateway.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/schedule', methods=['POST'])
def schedule():
    data = request.get_json()
    # TODO: Implement Redis caching, serialization, and communication with C++ solver
    return jsonify({"schedule": []})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /opt/oracle/reference_gateway.py
# Reference implementation
import heapq

def solve(jobs, dependencies):
    adj = {i: [] for i in range(jobs)}
    in_degree = {i: 0 for i in range(jobs)}
    for u, v in dependencies:
        adj[u].append(v)
        in_degree[v] += 1

    pq = [i for i in range(jobs) if in_degree[i] == 0]
    heapq.heapify(pq)

    order = []
    while pq:
        u = heapq.heappop(pq)
        order.append(u)
        for v in adj[u]:
            in_degree[v] -= 1
            if in_degree[v] == 0:
                heapq.heappush(pq, v)
    return order
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod -R 777 /home/user
