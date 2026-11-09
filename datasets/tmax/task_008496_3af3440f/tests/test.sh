#!/bin/bash
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import os
import runpy
import secrets
import stat
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.image as mpimg
import matplotlib.pyplot as plt
import numpy as np
import pytest
from matplotlib.axes import Axes
from matplotlib.colors import to_rgba

HOME = "/home/user"
STATE = {}


def regular_nonempty(path):
    st = os.lstat(path)
    return stat.S_ISREG(st.st_mode) and st.st_size > 0


def make_network_data():
    # Generate a fresh, unpredictable input so precomputed outputs cannot pass.
    graphs = []
    for i in range(8):
        v = 6 + secrets.randbelow(4)
        edges = []
        if i == 0:
            # Deliberately leave V-1 unreachable.
            for u in range(v - 2):
                edges.append((u, u + 1, 1 + secrets.randbelow(90)))
            edges.append((0, v - 2, 1 + secrets.randbelow(90)))
        else:
            # A connected chain plus competing shortcuts and a heavier parallel edge.
            for u in range(v - 1):
                edges.append((u, u + 1, 1 + secrets.randbelow(90)))
            edges.append((0, v - 1, 30 + secrets.randbelow(180)))
            edges.append((0, v // 2, 1 + secrets.randbelow(100)))
            edges.append((v // 2, v - 1, 1 + secrets.randbelow(100)))
            edges.append((0, 1, 120 + secrets.randbelow(80)))
        graphs.append((v, edges))

    with open(f"{HOME}/network_data.txt", "w") as f:
        f.write(f"{len(graphs)}\n")
        for v, edges in graphs:
            f.write(f"{v} {len(edges)}\n")
            for u, w, cost in edges:
                f.write(f"{u} {w} {cost}\n")


REFERENCE_CPP = r'''
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <queue>
#include <random>
#include <utility>
#include <vector>
using namespace std;

int main() {
    ifstream in("/home/user/network_data.txt");
    int N;
    if (!(in >> N) || N <= 0) return 2;
    vector<int> distances;
    for (int g = 0; g < N; ++g) {
        int V, E;
        if (!(in >> V >> E) || V <= 0 || E < 0) return 3;
        vector<vector<pair<int,int>>> adj(V);
        for (int j = 0; j < E; ++j) {
            int u, v, w;
            if (!(in >> u >> v >> w)) return 4;
            adj[u].push_back({v,w});
            adj[v].push_back({u,w});
        }
        const int INF = 1000000000;
        vector<int> d(V, INF);
        priority_queue<pair<int,int>, vector<pair<int,int>>, greater<pair<int,int>>> q;
        d[0] = 0;
        q.push({0,0});
        while (!q.empty()) {
            auto cur = q.top(); q.pop();
            int du = cur.first, u = cur.second;
            if (du != d[u]) continue;
            for (auto e : adj[u]) {
                int v = e.first, w = e.second;
                if (d[u] + w < d[v]) {
                    d[v] = d[u] + w;
                    q.push({d[v],v});
                }
            }
        }
        distances.push_back(d[V-1] == INF ? 0 : d[V-1]);
    }

    mt19937 gen(42);
    uniform_int_distribution<int> pick(0, N - 1);
    vector<double> means(10000);
    ofstream out("/tmp/reference_means.txt");
    out << setprecision(17);
    for (int i = 0; i < 10000; ++i) {
        double sum = 0;
        for (int j = 0; j < N; ++j) sum += distances[pick(gen)];
        means[i] = sum / N;
        out << means[i] << '\n';
    }
    sort(means.begin(), means.end());
    cout << fixed << setprecision(2)
         << "Lower: " << means[250] << ", Upper: " << means[9750] << '\n';
    cerr << setprecision(17) << means[250] << ' ' << means[9750] << '\n';
    return 0;
}
'''


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submission():
    profile_cpp = f"{HOME}/profile.cpp"
    plot_py = f"{HOME}/plot.py"
    assert os.path.exists(profile_cpp), "Missing /home/user/profile.cpp"
    assert os.path.exists(plot_py), "Missing /home/user/plot.py"
    assert regular_nonempty(profile_cpp), "profile.cpp must be a nonempty regular file"
    assert regular_nonempty(plot_py), "plot.py must be a nonempty regular file"

    make_network_data()

    with open("/tmp/reference_solver.cpp", "w") as f:
        f.write(REFERENCE_CPP)
    subprocess.run(
        ["g++", "-O2", "/tmp/reference_solver.cpp", "-o", "/tmp/reference_solver"],
        check=True, timeout=30
    )
    ref = subprocess.run(
        ["/tmp/reference_solver"], capture_output=True, text=True, check=True, timeout=30
    )
    STATE["expected_ci"] = ref.stdout.strip()
    STATE["bounds"] = tuple(float(x) for x in ref.stderr.strip().split())
    with open("/tmp/reference_means.txt") as f:
        STATE["expected_means"] = [float(x.strip()) for x in f]

    subprocess.run(
        ["g++", "-O2", profile_cpp, "-o", "/tmp/submitted_profile"],
        check=True, timeout=30
    )
    for path in (f"{HOME}/bootstrap_means.txt", f"{HOME}/ci_result.txt", f"{HOME}/distribution.png"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    subprocess.run(["/tmp/submitted_profile"], cwd=HOME, check=True, timeout=60)
    yield


def test_bootstrap_means_file():
    path = f"{HOME}/bootstrap_means.txt"
    assert os.path.exists(path), f"Missing file: {path}"
    assert regular_nonempty(path), f"{path} must be a nonempty regular file"
    with open(path) as f:
        lines = f.readlines()
    assert len(lines) == 10000, f"Expected exactly 10000 lines in {path}, found {len(lines)}"
    try:
        actual = [float(line.strip()) for line in lines]
    except ValueError:
        pytest.fail(f"Not all lines in {path} are valid floats.")
    assert all(np.isfinite(actual)), "Bootstrap means must all be finite"
    assert actual == STATE["expected_means"], "Bootstrap means or their generation order are incorrect"


def test_ci_result_file():
    path = f"{HOME}/ci_result.txt"
    assert os.path.exists(path), f"Missing file: {path}"
    with open(path) as f:
        content = f.read().strip()
    assert content == STATE["expected_ci"], (
        f"Content of {path} is incorrect. Expected '{STATE['expected_ci']}', got '{content}'"
    )


def test_plot_script_and_distribution():
    # Execute the submitted visualization while observing the actual matplotlib calls.
    with open(f"{HOME}/bootstrap_means.txt") as f:
        expected_data = np.array([float(x.strip()) for x in f])

    hist_calls = []
    original_hist = Axes.hist

    def observed_hist(self, x, *args, **kwargs):
        result = original_hist(self, x, *args, **kwargs)
        hist_calls.append((np.asarray(x, dtype=float).ravel(), len(result[1]) - 1))
        return result

    Axes.hist = observed_hist
    plt.close("all")
    try:
        runpy.run_path(f"{HOME}/plot.py", run_name="__main__")
    finally:
        Axes.hist = original_hist

    assert hist_calls, "plot.py did not create a matplotlib histogram"
    assert any(
        bins == 50 and len(data) == 10000 and np.array_equal(data, expected_data)
        for data, bins in hist_calls
    ), "plot.py must histogram all generated bootstrap means using exactly 50 bins"

    figures = [plt.figure(n) for n in plt.get_fignums()]
    axes = [ax for fig in figures for ax in fig.axes]
    assert any(ax.get_title() == "Bootstrap Distribution of Mean Routing Costs" for ax in axes), (
        "The required plot title is missing"
    )

    lower, upper = STATE["bounds"]
    found = {"lower": False, "upper": False}
    for ax in axes:
        for line in ax.lines:
            x = np.asarray(line.get_xdata(), dtype=float)
            if x.size < 2 or not np.allclose(x, x[0]):
                continue
            if not np.allclose(to_rgba(line.get_color()), to_rgba("red")):
                continue
            if line.get_linestyle() != "--":
                continue
            if abs(float(x[0]) - lower) <= 0.006:
                found["lower"] = True
            if abs(float(x[0]) - upper) <= 0.006:
                found["upper"] = True
    assert found["lower"] and found["upper"], (
        "The plot must contain red dashed vertical lines at both confidence bounds"
    )

    path = f"{HOME}/distribution.png"
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.getsize(path) > 0, f"File {path} is empty"
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "distribution.png is not a PNG file"
    image = mpimg.imread(path)
    assert image.size > 0 and image.ndim in (2, 3), "distribution.png is not a valid rendered image"
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
