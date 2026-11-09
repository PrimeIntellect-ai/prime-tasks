#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    # Create directories
    mkdir -p /app /home/user/corpus/clean /home/user/corpus/evil /eval/corpus/clean /eval/corpus/evil

    # Python script to generate corpora
    cat << 'EOF' > /tmp/gen_data.py
import json
import random
import os

def generate_plan(is_evil):
    def make_clean_node(depth=0):
        choices = ["Hash Join", "Seq Scan", "Index Scan", "Nested Loop"]
        ntype = random.choice(choices)
        node = {"Node Type": ntype}

        if ntype == "Seq Scan":
            node["Relation Name"] = random.choice(["users", "orders", "products"])
        elif ntype == "Index Scan":
            node["Index Name"] = random.choice(["idx_users_id", "idx_orders_date", "idx_backup_123"])
        elif ntype == "Nested Loop":
            if random.choice([True, False]):
                node["Join Filter"] = "(a.id = b.id)"
                node["Plans"] = [make_leaf(), make_leaf()]
            else:
                child1 = make_leaf()
                child2 = make_leaf()
                child1["Index Name"] = "idx_backup_foo"
                node["Plans"] = [child1, child2]

        if depth < 2 and "Plans" not in node:
            if random.choice([True, False]):
                node["Plans"] = [make_clean_node(depth+1)]
        return node

    def make_leaf():
        return {"Node Type": "Index Scan", "Index Name": random.choice(["idx_a", "idx_b"])}

    def make_evil_node():
        if random.choice([True, False]):
            node = {"Node Type": "Nested Loop"}
            child1 = make_leaf()
            child2 = make_leaf()
            child1["Index Name"] = "idx_other1"
            child2["Index Name"] = "idx_other2"
            node["Plans"] = [child1, child2]
            return node
        else:
            return {"Node Type": "Seq Scan", "Relation Name": "large_archive_table"}

    if is_evil:
        root = make_clean_node()
        evil = make_evil_node()
        if "Plans" not in root:
            root["Plans"] = []
        root["Plans"].append(evil)
        return [{"Plan": root}]
    else:
        return [{"Plan": make_clean_node()}]

def create_corpus(path, is_evil, count):
    os.makedirs(path, exist_ok=True)
    for i in range(count):
        with open(os.path.join(path, f"plan_{i}.json"), "w") as f:
            json.dump(generate_plan(is_evil), f)

create_corpus("/home/user/corpus/clean", False, 50)
create_corpus("/home/user/corpus/evil", True, 50)
create_corpus("/eval/corpus/clean", False, 50)
create_corpus("/eval/corpus/evil", True, 50)
EOF
    python3 /tmp/gen_data.py

    # Go source for oracle
    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"strings"
)

type PlanNode struct {
	NodeType     string      `json:"Node Type"`
	JoinFilter   interface{} `json:"Join Filter"`
	IndexName    string      `json:"Index Name"`
	RelationName string      `json:"Relation Name"`
	Plans        []PlanNode  `json:"Plans"`
}

func checkNode(node PlanNode) bool {
	if node.NodeType == "Seq Scan" && node.RelationName == "large_archive_table" {
		return true
	}
	if node.NodeType == "Nested Loop" && node.JoinFilter == nil {
		hasBackupIdx := false
		for _, child := range node.Plans {
			if strings.HasPrefix(child.IndexName, "idx_backup_") {
				hasBackupIdx = true
				break
			}
		}
		if !hasBackupIdx {
			return true
		}
	}
	for _, child := range node.Plans {
		if checkNode(child) {
			return true
		}
	}
	return false
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("INVALID")
		return
	}
	data, err := ioutil.ReadFile(os.Args[1])
	if err != nil {
		fmt.Println("INVALID")
		return
	}
	var root []struct {
		Plan PlanNode `json:"Plan"`
	}
	if err := json.Unmarshal(data, &root); err != nil || len(root) == 0 {
		fmt.Println("INVALID")
		return
	}
	if checkNode(root[0].Plan) {
		fmt.Println("INVALID")
	} else {
		fmt.Println("VALID")
	}
}
EOF
    cd /tmp && go build -ldflags="-s -w" -o /app/plan_validator oracle.go
    rm /tmp/oracle.go /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /eval
