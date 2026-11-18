#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/gateway
    cd /home/user/gateway
    go mod init gateway

    cat << 'EOF' > /home/user/gateway/router.go
package gateway

import (
	"regexp"
	"strings"
)

type Router struct {
	routes map[*regexp.Regexp]string
}

func NewRouter() *Router {
	return &Router{
		routes: make(map[*regexp.Regexp]string),
	}
}

// Register adds a route like "/users/{id:int}"
func (r *Router) Register(pattern string, handlerName string) {
	// BUG: missing anchors ^ and $ causing partial matches
	// BUG: int constraint [0-9]+ will match "123a" partially if not anchored
	regexPattern := strings.ReplaceAll(pattern, "{id:int}", "(?P<id>[0-9]+)")
	compiled := regexp.MustCompile(regexPattern)
	r.routes[compiled] = handlerName
}

// Match returns the handler name and extracted params if it matches
func (r *Router) Match(path string) (string, map[string]string, bool) {
	for regex, handler := range r.routes {
		if regex.MatchString(path) {
			matches := regex.FindStringSubmatch(path)
			params := make(map[string]string)
			for i, name := range regex.SubexpNames() {
				if i != 0 && name != "" {
					params[name] = matches[i]
				}
			}
			return handler, params, true
		}
	}
	return "", nil, false
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
