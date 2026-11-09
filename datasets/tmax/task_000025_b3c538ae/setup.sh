#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/build_graph.proto
syntax = "proto3";

message Module {
  string name = 1;
  repeated string depends_on = 2;
}

message BuildGraph {
  repeated Module modules = 1;
}

message BuildOrder {
  repeated string ordered_modules = 1;
}
EOF

    cat << 'EOF' > /home/user/legacy_solver.rb
def resolve(modules)
  in_degree = Hash.new(0)
  adj = Hash.new { |h, k| h[k] = [] }

  modules.each do |mod|
    in_degree[mod[:name]] ||= 0
    mod[:depends_on].each do |dep|
      adj[dep] << mod[:name]
      in_degree[mod[:name]] += 1
      in_degree[dep] ||= 0
    end
  end

  queue = in_degree.select { |_, v| v == 0 }.keys.sort
  result = []

  while !queue.empty?
    # pop first alphabetically
    u = queue.shift
    result << u

    adj[u].each do |v|
      in_degree[v] -= 1
      if in_degree[v] == 0
        queue << v
        queue.sort!
      end
    end
  end

  raise "Cycle detected" if result.size != in_degree.size
  result
end
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
