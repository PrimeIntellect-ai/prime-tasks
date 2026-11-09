#!/bin/bash
set +e
mkdir -p /logs/verifier

if (
    set -e

    workdir=$(mktemp -d /tmp/network_verifier.XXXXXX)
    cp -p /home/user/graph.txt "$workdir/graph.original"
    cp -p /home/user/y.txt "$workdir/y.original"

    cleanup() {
        cp -p "$workdir/graph.original" /home/user/graph.txt
        cp -p "$workdir/y.original" /home/user/y.txt
        if [ -f "$workdir/results.original.json" ]; then
            cp -p "$workdir/results.original.json" /home/user/results.json
        else
            rm -f /home/user/results.json
        fi
        rm -rf "$workdir"
    }
    trap cleanup EXIT

    mapfile -d '' cpp_sources < <(find /home/user -type f \( -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' \) -print0)
    if [ "${#cpp_sources[@]}" -eq 0 ]; then
        echo 'No C++ source file found under /home/user' >&2
        exit 1
    fi

    g++ -std=c++17 -O2 -I/usr/include/eigen3 "${cpp_sources[@]}" -o "$workdir/submission_program"
    chmod 755 "$workdir/submission_program"

    cat > "$workdir/reference.cpp" <<'CPP_EOF'
#include <Eigen/Dense>
#include <Eigen/Eigenvalues>
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <stdexcept>
#include <utility>
#include <vector>

using Eigen::MatrixXd;
using Eigen::Vector2d;
using Eigen::VectorXd;

static Vector2d fit(const MatrixXd& X, const VectorXd& y) {
    Vector2d w = Vector2d::Zero();
    const double n = static_cast<double>(X.rows());
    for (int iteration = 0; iteration < 1000; ++iteration) {
        w -= 0.1 * (X.transpose() * (X * w - y)) / n;
    }
    return w;
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    constexpr int N = 50;
    MatrixXd adjacency = MatrixXd::Zero(N, N);

    std::ifstream graph("/home/user/graph.txt");
    if (!graph) return 3;
    int u, v;
    while (graph >> u >> v) {
        if (u < 0 || u >= N || v < 0 || v >= N || u == v) return 4;
        adjacency(u, v) = 1.0;
        adjacency(v, u) = 1.0;
    }
    if (!graph.eof()) return 5;

    VectorXd y(N);
    std::ifstream observed("/home/user/y.txt");
    if (!observed) return 6;
    for (int i = 0; i < N; ++i) {
        if (!(observed >> y(i))) return 7;
    }
    double extra;
    if (observed >> extra) return 8;

    MatrixXd laplacian = -adjacency;
    for (int i = 0; i < N; ++i) {
        laplacian(i, i) = adjacency.row(i).sum();
    }

    Eigen::SelfAdjointEigenSolver<MatrixXd> solver(laplacian);
    if (solver.info() != Eigen::Success) return 9;
    MatrixXd X = solver.eigenvectors().middleCols(1, 2);
    Vector2d w = fit(X, y);

    std::mt19937 gen(42);
    std::uniform_int_distribution<int> dist(0, 49);
    std::vector<double> bootstrap0;
    std::vector<double> bootstrap1;
    bootstrap0.reserve(1000);
    bootstrap1.reserve(1000);

    for (int b = 0; b < 1000; ++b) {
        MatrixXd sampledX(N, 2);
        VectorXd sampledY(N);
        for (int i = 0; i < N; ++i) {
            int index = dist(gen);
            sampledX.row(i) = X.row(index);
            sampledY(i) = y(index);
        }
        Vector2d sampledW = fit(sampledX, sampledY);
        bootstrap0.push_back(sampledW(0));
        bootstrap1.push_back(sampledW(1));
    }

    std::sort(bootstrap0.begin(), bootstrap0.end());
    std::sort(bootstrap1.begin(), bootstrap1.end());

    std::ofstream output(argv[1]);
    if (!output) return 10;
    output << std::setprecision(17)
           << "{\n"
           << "  \"w0\": " << w(0) << ",\n"
           << "  \"w1\": " << w(1) << ",\n"
           << "  \"w0_lower\": " << bootstrap0[25] << ",\n"
           << "  \"w0_upper\": " << bootstrap0[975] << ",\n"
           << "  \"w1_lower\": " << bootstrap1[25] << ",\n"
           << "  \"w1_upper\": " << bootstrap1[975] << "\n"
           << "}\n";
    return output ? 0 : 11;
}
CPP_EOF
    g++ -std=c++17 -O2 -I/usr/include/eigen3 "$workdir/reference.cpp" -o "$workdir/reference_program"

    cat > "$workdir/check.py" <<'PY_EOF'
import json
import math
import sys

submission_path, reference_path, mode = sys.argv[1:]
expected_keys = {"w0", "w1", "w0_lower", "w0_upper", "w1_lower", "w1_upper"}

with open(submission_path, "r") as f:
    data = json.load(f)
with open(reference_path, "r") as f:
    reference = json.load(f)

assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}"
for key, value in data.items():
    assert isinstance(value, (int, float)), f"Value for {key} must be a number"
    assert not isinstance(value, bool), f"Value for {key} must be a number"
    assert math.isfinite(float(value)), f"Value for {key} must be finite"

# Validate every requested result against an independently recomputed Eigen/GD/bootstrap run.
for key in expected_keys:
    error = abs(float(data[key]) - float(reference[key]))
    assert error <= 2e-4, (
        f"{key}={data[key]} differs from recomputed value {reference[key]} "
        f"by {error}"
    )

if mode == "original":
    w0 = data["w0"]
    w1 = data["w1"]
    assert abs(abs(w0) - 2.5) < 0.5, f"w0 magnitude {abs(w0)} is too far from expected ~2.5"
    assert abs(abs(w1) - 1.5) < 0.5, f"w1 magnitude {abs(w1)} is too far from expected ~1.5"
    assert data["w0_lower"] <= w0 <= data["w0_upper"], "w0 must be within its bootstrap bounds"
    assert data["w1_lower"] <= w1 <= data["w1_upper"], "w1 must be within its bootstrap bounds"
    w0_width = data["w0_upper"] - data["w0_lower"]
    w1_width = data["w1_upper"] - data["w1_lower"]
    assert 0.01 < w0_width < 1.0, f"w0 bound width {w0_width} is unreasonable"
    assert 0.01 < w1_width < 1.0, f"w1 bound width {w1_width} is unreasonable"
PY_EOF

    run_submission() {
        rm -f /home/user/results.json
        chmod 444 /home/user/graph.txt /home/user/y.txt
        (cd /home/user && timeout 180s runuser -u user -- env HOME=/home/user "$workdir/submission_program")
        test -f /home/user/results.json
    }

    # Check the required result on the original task inputs.
    run_submission
    cp -p /home/user/results.json "$workdir/results.original.json"
    "$workdir/reference_program" "$workdir/reference.original.json"
    python3 "$workdir/check.py" /home/user/results.json "$workdir/reference.original.json" original

    # Exercise the program on a derived input as well, preventing a fixed JSON writer
    # from passing while keeping the same dimensions and required algorithm.
    python3 - "$workdir/graph.original" "$workdir/y.original" <<'PY_EOF'
import math
import sys

graph_path, y_path = sys.argv[1:]
edges = set()
with open(graph_path) as f:
    for line in f:
        if line.strip():
            u, v = map(int, line.split())
            edges.add(tuple(sorted((u, v))))
edge = (0, 1)
if edge in edges:
    edges.remove(edge)
else:
    edges.add(edge)
with open('/home/user/graph.txt', 'w') as f:
    for u, v in sorted(edges):
        f.write(f'{u} {v}\n')
with open(y_path) as f:
    values = [float(line) for line in f if line.strip()]
with open('/home/user/y.txt', 'w') as f:
    for i, value in enumerate(values):
        f.write(f'{value + 0.03 * math.cos(i + 0.25):.17g}\n')
PY_EOF

    run_submission
    "$workdir/reference_program" "$workdir/reference.challenge.json"
    python3 "$workdir/check.py" /home/user/results.json "$workdir/reference.challenge.json" challenge
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
