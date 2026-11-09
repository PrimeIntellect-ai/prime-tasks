#!/usr/bin/env python3
import sys
import math

def solve():
    if len(sys.argv) < 2:
        return
    s = sys.argv[1]
    N = int(math.isqrt(len(s)))
    adj = []
    for i in range(N):
        adj.append([int(x) for x in s[i*N:(i+1)*N]])

    in_degree = [0]*N
    for i in range(N):
        for j in range(N):
            if adj[i][j] == 1:
                in_degree[j] += 1

    import heapq
    q = []
    for i in range(N):
        if in_degree[i] == 0:
            heapq.heappush(q, i)

    res = []
    while q:
        u = heapq.heappop(q)
        res.append(u)
        for v in range(N):
            if adj[u][v] == 1:
                in_degree[v] -= 1
                if in_degree[v] == 0:
                    heapq.heappush(q, v)

    if len(res) == N:
        print(" ".join(map(str, res)))
    else:
        print("CYCLE DETECTED")

if __name__ == '__main__':
    solve()
