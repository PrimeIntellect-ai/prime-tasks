#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendor/go-graphdoc
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create go-graphdoc package
    cat << 'EOF' > /app/vendor/go-graphdoc/go.mod
module go-graphdoc

go 1.18
EOF

    cat << 'EOF' > /app/vendor/go-graphdoc/parser.go
package graphdoc

import (
	"encoding/json"
	"errors"
	"os"
	"regexp"
)

// Bug: Missing 0-9 in regex
var fieldRegex = regexp.MustCompile("^[a-zA-Z_$][a-zA-Z_]*$")

type PipelineStage map[string]interface{}

func ParsePipeline(data []byte) ([]PipelineStage, error) {
	// Bug: Hardcoded environment check
	if os.Getenv("GRAPH_ENV") != "production" {
		return nil, errors.New("unsupported env")
	}

	var pipeline []PipelineStage
	if err := json.Unmarshal(data, &pipeline); err != nil {
		return nil, err
	}

	// Dummy check to ensure regex is used
	if !fieldRegex.MatchString("dummy_field") {
		return nil, errors.New("invalid field name detected")
	}

	return pipeline, nil
}
EOF

    # Create clean corpus
    cat << 'EOF' > /home/user/corpus/clean/clean_1.json
[
    {"$match": {"status": "active"}},
    {"$project": {"gene_id": 1, "expression_level": 1}}
]
EOF

    cat << 'EOF' > /home/user/corpus/clean/clean_2.json
[
    {"$match": {"disease": "cancer"}},
    {"$graphLookup": {"from": "pathways", "startWith": "$pathway_id", "connectFromField": "pathway_id", "connectToField": "parent_id", "as": "hierarchy", "maxDepth": 4}}
]
EOF

    # Create evil corpus
    cat << 'EOF' > /home/user/corpus/evil/evil_1.json
[
    {"$match": {"status": "active"}},
    {"$graphLookup": {"from": "genes", "startWith": "$gene_id", "connectFromField": "gene_id", "connectToField": "interacts_with", "as": "interactions"}}
]
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil_2.json
[
    {"$graphLookup": {"from": "variants", "startWith": "$variant_id", "connectFromField": "variant_id", "connectToField": "linked_variant", "as": "linkage", "maxDepth": 10}}
]
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil_3.json
[
    {"$match": {"experiment_id": "EXP123"}},
    {"$project": {"_internal_patient_id": 1, "results": 1}}
]
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil_4.json
[
    {"$project": {"auth_token": 1}}
]
EOF

    # Set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
