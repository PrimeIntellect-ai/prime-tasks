#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go diffutils
    pip3 install pytest

    mkdir -p /home/user/migrator
    cd /home/user/migrator
    go mod init migrator

    cat << 'EOF' > legacy.json
[
  {"id": 1, "data": "A", "values": [9, 2, 5]},
  {"id": 2, "data": "B", "values": [8]},
  {"id": 1, "data": "C", "values": [1, 7]}
]
EOF

    cat << 'EOF' > main.go
package main

import (
	"encoding/json"
	"io/ioutil"
	"os"
)

func main() {
	if len(os.Args) < 3 {
		os.Exit(1)
	}
	inBytes, _ := ioutil.ReadFile(os.Args[1])
	var legacy []Legacy
	json.Unmarshal(inBytes, &legacy)

	modern := Migrate(legacy)

	outBytes, _ := json.MarshalIndent(modern, "", "  ")
	ioutil.WriteFile(os.Args[2], outBytes, 0644)
}
EOF

    cat << 'EOF' > migrate.go
package main

import (
	"sort"
)

type Legacy struct {
	ID     int    `json:"id"`
	Data   string `json:"data"`
	Values []int  `json:"values"`
}

type Modern struct {
	ID           int    `json:"id"`
	MergedData   string `json:"merged_data"`
	SortedValues []int  `json:"sorted_values"`
}

func Migrate(records []Legacy) []Modern {
	m := make(map[int]*Modern)
	for _, r := range records {
		if _, exists := m[r.ID]; !exists {
			m[r.ID] = &Modern{ID: r.ID}
		}
		m[r.ID].MergedData += r.Data
		m[r.ID].SortedValues = append(m[r.ID].SortedValues, r.Values...)
	}

	var results []Modern
	for _, mod := range m {
		// INTENTIONAL COMPILE ERROR: returning pointer instead of value
		// INTENTIONAL LOGIC ERROR: missing sorting of SortedValues
		results = append(results, mod) // compilation fails here: mod is *Modern, results is []Modern
	}

	// Sort results by ID for deterministic output
	sort.Slice(results, func(i, j int) bool {
		return results[i].ID < results[j].ID
	})

	return &results // compilation fails here: returning pointer to slice
}
EOF

    cat << 'EOF' > migrate_test.go
package main

import (
	"reflect"
	"sort"
	"testing"
	"testing/quick"
)

func TestMigrateProperties(t *testing.T) {
	f := func(records []Legacy) bool {
		moderns := Migrate(records)

		for _, m := range moderns {
			if !sort.IntsAreSorted(m.SortedValues) {
				return false
			}
		}
		return true
	}

	if err := quick.Check(f, &quick.Config{MaxCount: 100}); err != nil {
		t.Error(err)
	}
}

func TestMigrateLogic(t *testing.T) {
	input := []Legacy{
		{ID: 1, Data: "X", Values: []int{3, 1}},
		{ID: 1, Data: "Y", Values: []int{2}},
	}
	expected := []Modern{
		{ID: 1, MergedData: "XY", SortedValues: []int{1, 2, 3}},
	}

	out := Migrate(input)
	if !reflect.DeepEqual(out, expected) {
		t.Fatalf("Expected %v, got %v", expected, out)
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/migrator
    chmod -R 777 /home/user
