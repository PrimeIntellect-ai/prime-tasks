#!/bin/bash
set +e
mkdir -p /logs/verifier

TMPDIR=$(mktemp -d)
cp /home/user/graph.txt "$TMPDIR/original_graph.txt"

cleanup() {
    cp "$TMPDIR/original_graph.txt" /home/user/graph.txt 2>/dev/null || true
    if [ -f "$TMPDIR/original_results.txt" ]; then
        cp "$TMPDIR/original_results.txt" /home/user/results.txt 2>/dev/null || true
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

verify() {
    cat > "$TMPDIR/oracle.cpp" <<'CPP_EOF'
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <queue>
#include <random>
#include <utility>
#include <vector>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::ifstream in(argv[1]);
    if (!in) return 2;

    std::vector<std::pair<int, int>> edges;
    int u, v, max_vertex = -1;
    while (in >> u >> v) {
        if (u < 0 || v < 0) return 2;
        edges.push_back({u, v});
        max_vertex = std::max(max_vertex, std::max(u, v));
    }
    if (max_vertex < 0) return 2;

    std::vector<std::vector<int>> adjacency(max_vertex + 1);
    for (const auto &edge : edges) {
        adjacency[edge.first].push_back(edge.second);
        adjacency[edge.second].push_back(edge.first);
    }
    for (auto &neighbors : adjacency)
        std::sort(neighbors.begin(), neighbors.end());

    std::vector<int> distance(adjacency.size(), -1);
    std::queue<int> pending;
    distance[0] = 0;
    pending.push(0);
    while (!pending.empty()) {
        int current = pending.front();
        pending.pop();
        for (int next : adjacency[current]) {
            if (distance[next] == -1) {
                distance[next] = distance[current] + 1;
                pending.push(next);
            }
        }
    }
    for (int &d : distance)
        if (d < 0) d = 0;

    std::vector<long long> squared_distance_sum(101, 0);
    std::mt19937 generator(42);
    for (int walker = 0; walker < 10000; ++walker) {
        int current = 0;
        for (int time = 1; time <= 100; ++time) {
            if (adjacency[current].empty()) return 2;
            std::uniform_int_distribution<int> pick(
                0, static_cast<int>(adjacency[current].size()) - 1);
            current = adjacency[current][pick(generator)];
            long long d = distance[current];
            squared_distance_sum[time] += d * d;
        }
    }

    std::vector<double> msd(101, 0.0);
    for (int time = 1; time <= 100; ++time)
        msd[time] = static_cast<double>(squared_distance_sum[time]) / 10000.0;

    double mean_x = 0.0, mean_y = 0.0;
    for (int time = 10; time <= 100; ++time) {
        mean_x += std::log(static_cast<double>(time));
        mean_y += std::log(msd[time]);
    }
    mean_x /= 91.0;
    mean_y /= 91.0;

    double numerator = 0.0, denominator = 0.0;
    for (int time = 10; time <= 100; ++time) {
        double x = std::log(static_cast<double>(time));
        double y = std::log(msd[time]);
        numerator += (x - mean_x) * (y - mean_y);
        denominator += (x - mean_x) * (x - mean_x);
    }
    double alpha = numerator / denominator;

    double integral = 0.0;
    for (int time = 1; time < 100; ++time)
        integral += (msd[time] + msd[time + 1]) / 2.0;

    std::cout << std::fixed << std::setprecision(3)
              << "Alpha: " << alpha << '\n'
              << "Integral: " << integral << '\n';
    return 0;
}
CPP_EOF

    g++ -O3 -std=c++17 "$TMPDIR/oracle.cpp" -o "$TMPDIR/oracle" || return 1

    test -f /home/user/analyze_network.cpp || return 1
    g++ -O3 -std=c++17 /home/user/analyze_network.cpp -o "$TMPDIR/analyze_network" || return 1

    rm -f /home/user/results.txt
    (cd /home/user && timeout 60s "$TMPDIR/analyze_network") || return 1

    cat > "$TMPDIR/test_final_state.py" <<'PY_EOF'
import os
import re

def test_results_file_exists():
    assert os.path.exists('/home/user/results.txt'), "The results file /home/user/results.txt is missing."

def test_results_content():
    with open('/home/user/results.txt', 'r') as f:
        content = f.read()

    alpha_match = re.search(r'Alpha:\s*([0-9.]+)', content)
    assert alpha_match is not None, "Alpha value not found in results.txt. Check the output format."
    alpha = float(alpha_match.group(1))
    assert abs(alpha - 0.963) <= 0.005, f"Expected Alpha to be approximately 0.963, but got {alpha}"

    integral_match = re.search(r'Integral:\s*([0-9.]+)', content)
    assert integral_match is not None, "Integral value not found in results.txt. Check the output format."
    integral = float(integral_match.group(1))
    assert abs(integral - 1063.310) <= 0.05, f"Expected Integral to be approximately 1063.310, but got {integral}"

def test_cpp_file_exists():
    assert os.path.exists('/home/user/analyze_network.cpp'), "The source code file /home/user/analyze_network.cpp is missing."
PY_EOF

    python3 -m pytest "$TMPDIR/test_final_state.py" -x --tb=short || return 1
    cp /home/user/results.txt "$TMPDIR/original_results.txt" || return 1

    for case_number in 1 2; do
        CASE_NUMBER="$case_number" python3 - <<'PY_EOF' || return 1
import os
import random
import secrets

case_number = int(os.environ['CASE_NUMBER'])
rng = random.Random(secrets.randbits(128))
n = rng.randint(14, 28)
edges = set()

# Start with a random tree so every contiguous vertex ID is present and reachable.
for vertex in range(1, n):
    parent = rng.randrange(vertex)
    edges.add((min(parent, vertex), max(parent, vertex)))

# Add enough non-tree edges to exercise varying degrees and alternative paths.
target = (2 + case_number) * n
while len(edges) < target:
    a, b = rng.sample(range(n), 2)
    edges.add((min(a, b), max(a, b)))

edge_list = list(edges)
rng.shuffle(edge_list)
with open('/home/user/graph.txt', 'w') as output:
    for a, b in edge_list:
        output.write(f'{a} {b}\n')
PY_EOF

        cp /home/user/graph.txt "$TMPDIR/case_graph.txt" || return 1
        rm -f /home/user/results.txt
        (cd /home/user && timeout 60s "$TMPDIR/analyze_network") || return 1
        test -f /home/user/results.txt || return 1
        "$TMPDIR/oracle" "$TMPDIR/case_graph.txt" > "$TMPDIR/expected.txt" || return 1

        python3 - "$TMPDIR/expected.txt" /home/user/results.txt <<'PY_EOF' || return 1
import math
import re
import sys

expected_path, actual_path = sys.argv[1:]
pattern = re.compile(r'\AAlpha: (-?\d+\.\d{3})\nIntegral: (-?\d+\.\d{3})\n?\Z')

def read_result(path):
    with open(path, 'r') as stream:
        text = stream.read()
    match = pattern.fullmatch(text)
    assert match is not None, f'Incorrect results.txt format: {text!r}'
    values = tuple(float(value) for value in match.groups())
    assert all(math.isfinite(value) for value in values)
    return values

expected = read_result(expected_path)
actual = read_result(actual_path)
assert abs(actual[0] - expected[0]) <= 0.0011, (actual, expected)
assert abs(actual[1] - expected[1]) <= 0.0011, (actual, expected)
PY_EOF
    done

    return 0
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
