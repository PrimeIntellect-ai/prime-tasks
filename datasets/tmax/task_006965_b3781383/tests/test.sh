#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import secrets
import stat
import subprocess

SCRIPT = "/home/user/clustering.py"
DATA = "/home/user/data.csv"
CORRUPTED = "/home/user/corrupted_lines.txt"
CENTROIDS = "/home/user/centroids.txt"


def get_expected_results(data_path=DATA):
    if not os.path.exists(data_path):
        return "4,8,12", "-5.0,11.0,102.33"

    corrupted_lines = []
    valid_data = []
    with open(data_path, "r") as f:
        for i, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                val = float(line)
                if abs(val) > 1000:
                    corrupted_lines.append(i)
                else:
                    valid_data.append(val)
            except ValueError:
                corrupted_lines.append(i)

    expected_corrupted = ",".join(map(str, corrupted_lines))

    k = 3
    if len(valid_data) >= k:
        centroids = valid_data[:k]
        for _ in range(100):
            clusters = [[] for _ in range(k)]
            for x in valid_data:
                distances = [abs(x - c) for c in centroids]
                closest = distances.index(min(distances))
                clusters[closest].append(x)

            new_centroids = []
            for i, cluster in enumerate(clusters):
                if not cluster:
                    new_centroids.append(centroids[i])
                else:
                    new_centroids.append(sum(cluster) / len(cluster))

            if new_centroids == centroids:
                break
            centroids = new_centroids

        expected_centroids = ",".join(
            str(round(c, 2)) for c in sorted(centroids)
        )
    else:
        expected_centroids = "-5.0,11.0,102.33"

    return expected_corrupted, expected_centroids


def run_script():
    for path in (CORRUPTED, CENTROIDS):
        if os.path.lexists(path):
            os.unlink(path)

    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"clustering.py failed with exit code {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_current_outputs(expected_corrupted, expected_centroids):
    assert os.path.isfile(CORRUPTED), f"File {CORRUPTED} was not generated."
    with open(CORRUPTED, "r") as f:
        content = f.read().strip()
    assert content == expected_corrupted, (
        f"Expected {CORRUPTED} to contain '{expected_corrupted}', but got '{content}'"
    )

    assert os.path.isfile(CENTROIDS), f"File {CENTROIDS} was not generated."
    with open(CENTROIDS, "r") as f:
        content = f.read().strip()
    assert content == expected_centroids, (
        f"Expected {CENTROIDS} to contain '{expected_centroids}', but got '{content}'"
    )


def test_script_executes_and_original_outputs_are_correct():
    assert os.path.exists(SCRIPT), f"File {SCRIPT} does not exist."
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"File {SCRIPT} is not a regular file."

    expected_corrupted, expected_centroids = get_expected_results()
    run_script()
    assert_current_outputs(expected_corrupted, expected_centroids)


def test_kmeans_retains_previous_centroid_for_empty_clusters():
    spec = importlib.util.spec_from_file_location("submitted_clustering", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    assert callable(getattr(module, "kmeans", None)), "kmeans function is missing"
    result = module.kmeans([0.0, 0.0, 0.0, 100.0], k=3, max_iters=1)
    assert result == [25.0, 0.0, 0.0], (
        "An empty cluster must retain its corresponding previous centroid"
    )


def test_script_handles_unseen_corruption_outliers_and_empty_clusters():
    original_data = open(DATA, "rb").read()
    saved_outputs = {}
    for path in (CORRUPTED, CENTROIDS):
        saved_outputs[path] = open(path, "rb").read() if os.path.isfile(path) else None

    base = secrets.randbelow(41) - 20
    garbage = "garbage_" + secrets.token_hex(10)
    lines = [
        f"{base}.0",
        f"{base}.0",
        f"{base}.0",
        garbage,
        f"{base - 30}.0",
        str(2001 + secrets.randbelow(5000)),
        f"{base + 80}.0",
        f"{base + 82}.0",
        str(-(2001 + secrets.randbelow(5000))),
        f"{base - 29}.0",
    ]

    try:
        with open(DATA, "w") as f:
            f.write("\n".join(lines) + "\n")

        expected_corrupted, expected_centroids = get_expected_results()
        assert expected_corrupted == "4,6,9"
        run_script()
        assert_current_outputs(expected_corrupted, expected_centroids)
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        for path, content in saved_outputs.items():
            if content is None:
                if os.path.lexists(path):
                    os.unlink(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
