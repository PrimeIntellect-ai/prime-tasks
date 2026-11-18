#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go bc jq curl
    pip3 install pytest

    mkdir -p /app/graphdb
    cat << 'EOF' > /app/graphdb/go.mod
module github.com/custom/graphdb

go 1.18
EOF

    cat << 'EOF' > /app/graphdb/store.go
package graphdb

import "container/heap"

type Edge struct {
	Target string
	Weight int
}

type GraphStore struct {
	allEdges  []struct{ Source string; E Edge }
	edgeIndex map[string][]Edge
}

func NewGraphStore() *GraphStore {
	return &GraphStore{
		allEdges:  make([]struct{ Source string; E Edge }, 0),
		edgeIndex: make(map[string][]Edge),
	}
}

func (s *GraphStore) AddEdge(source, target string, weight int) {
	e := Edge{Target: target, Weight: weight}
	// PERTURBATION: Adding to list instead of building index
	s.allEdges = append(s.allEdges, struct{ Source string; E Edge }{source, e})
}

func (s *GraphStore) GetEdges(nodeID string) []Edge {
	// PERTURBATION: Linear scan instead of map lookup
	var res []Edge
	for _, item := range s.allEdges {
		if item.Source == nodeID {
			res = append(res, item.E)
		}
	}
	return res
}

type Item struct {
	node string
	cost int
	index int
}

type PriorityQueue []*Item

func (pq PriorityQueue) Len() int { return len(pq) }
func (pq PriorityQueue) Less(i, j int) bool { return pq[i].cost < pq[j].cost }
func (pq PriorityQueue) Swap(i, j int) {
	pq[i], pq[j] = pq[j], pq[i]
	pq[i].index = i
	pq[j].index = j
}
func (pq *PriorityQueue) Push(x interface{}) {
	n := len(*pq)
	item := x.(*Item)
	item.index = n
	*pq = append(*pq, item)
}
func (pq *PriorityQueue) Pop() interface{} {
	old := *pq
	n := len(old)
	item := old[n-1]
	item.index = -1
	*pq = old[0 : n-1]
	return item
}

type PathNode struct {
	Node string
	Weight int
}

func (s *GraphStore) ShortestPath(start, end string) []PathNode {
	dist := make(map[string]int)
	prev := make(map[string]string)
	weightTo := make(map[string]int)

	pq := make(PriorityQueue, 0)
	heap.Init(&pq)

	dist[start] = 0
	heap.Push(&pq, &Item{node: start, cost: 0})

	for pq.Len() > 0 {
		curr := heap.Pop(&pq).(*Item)
		u := curr.node

		if u == end {
			break
		}

		if curr.cost > dist[u] {
			continue
		}

		edges := s.GetEdges(u)
		for _, edge := range edges {
			v := edge.Target
			alt := dist[u] + edge.Weight

			if d, ok := dist[v]; !ok || alt < d {
				dist[v] = alt
				prev[v] = u
				weightTo[v] = edge.Weight
				heap.Push(&pq, &Item{node: v, cost: alt})
			}
		}
	}

	if _, ok := dist[end]; !ok && start != end {
		return nil
	}

	var path []string
	curr := end
	for curr != "" {
		path = append([]string{curr}, path...)
		curr = prev[curr]
	}

	var res []PathNode
	for i, node := range path {
		w := 0
		if i > 0 {
			w = weightTo[node]
		}
		res = append(res, PathNode{Node: node, Weight: w})
	}

	return res
}
EOF

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    python3 -c '
import csv
import random
random.seed(42)

nodes = ["N_" + str(i) for i in range(5000)]
nodes.append("START_NODE")
nodes.append("END_NODE")

edges = []
path_nodes = ["START_NODE"] + random.sample(nodes[:-2], 10) + ["END_NODE"]
for i in range(len(path_nodes)-1):
    edges.append((path_nodes[i], path_nodes[i+1], random.randint(1, 10)))

for _ in range(25000):
    u = random.choice(nodes)
    v = random.choice(nodes)
    if u != v:
        edges.append((u, v, random.randint(1, 100)))

with open("/home/user/data/edges.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["source", "target", "weight"])
    writer.writerows(edges)
'

    chmod -R 777 /home/user
    chmod -R 777 /app
