#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/vendored/artparse
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /app/artifact-filter

    # Create vendored package go.mod
    cat << 'EOF' > /app/vendored/artparse/go.mod
module artparse

go 1.18
EOF

    # Create vendored package parser.go with deliberate bug
    cat << 'EOF' > /app/vendored/artparse/parser.go
package artparse

import (
	"strings"
)

type Artifact struct {
	Name   string
	Merges []string
	Links  []string
}

type Parser struct {
	state int
}

const (
	StateIdle = iota
	StateMerge
	StateLink
)

func (p *Parser) Parse(content string) (*Artifact, error) {
	art := &Artifact{}
	lines := strings.Split(content, "\n")

	p.state = StateIdle
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		if strings.HasPrefix(line, "NAME ") {
			art.Name = strings.TrimPrefix(line, "NAME ")
		} else if strings.HasPrefix(line, "MERGE ") {
			p.state = StateMerge
			art.Merges = append(art.Merges, strings.TrimPrefix(line, "MERGE "))
			// BUG: p.state = StateIdle is missing
			for p.state == StateMerge {
				// infinite loop
			}
		} else if strings.HasPrefix(line, "LINK ") {
			p.state = StateLink
			art.Links = append(art.Links, strings.TrimPrefix(line, "LINK "))
			p.state = StateIdle
		}
	}
	return art, nil
}

func Parse(content string) (*Artifact, error) {
	p := &Parser{}
	return p.Parse(content)
}
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.art
NAME CleanApp
MERGE BaseDep
LINK out/bin
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.art
NAME CleanTools
MERGE LibA
MERGE LibB
LINK build/output
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/evil1.art
NAME EvilApp
MERGE EvilApp
LINK out/bin
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.art
NAME EvilPath
MERGE BaseDep
LINK ../../etc/passwd
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
