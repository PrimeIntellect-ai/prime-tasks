#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

HOME = Path("/home/user")
SCRIPT = HOME / "pipeline.sh"
CPP = HOME / "detect.cpp"
ARTIFACTS = HOME / "artifacts.txt"
METRICS = HOME / "metrics.txt"
OUTPUT = HOME / "top_anomalies.txt"


def run(cmd, **kwargs):
    kwargs.setdefault("timeout", 20)
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def write_rows(path, rows):
    path.write_text("".join(" ".join(map(str, row)) + "\n" for row in rows))


def expected_ids(records):
    scored = []
    for artifact_id, size, error_rate in records:
        posterior = (error_rate * 0.05) / (
            error_rate * 0.05 + 0.01 * 0.95
        )
        distance = math.sqrt((posterior - 1.0) ** 2 + (size / 1000.0) ** 2)
        scored.append((distance, artifact_id))
    scored.sort()
    return [str(artifact_id) for _, artifact_id in scored[:3]]


def read_output(path=OUTPUT):
    assert path.is_file(), f"Output file not created: {path}"
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script is not executable: {script_path}"


def test_cpp_file_exists():
    cpp_path = "/home/user/detect.cpp"
    assert os.path.isfile(cpp_path), f"Missing C++ source file: {cpp_path}"


def test_pipeline_execution_and_output():
    # Preserve the original assertion on the supplied fixture.
    write_rows(ARTIFACTS, [(1, 500), (2, 10), (3, 1200), (4, 0), (5, 50)])
    write_rows(METRICS, [(1, 0.02), (2, 0.85), (3, 0.05), (4, 0.99), (5, 0.70)])

    if OUTPUT.exists():
        OUTPUT.unlink()

    result = run(["/bin/bash", str(SCRIPT)], cwd=str(HOME))
    assert result.returncode == 0, (
        f"pipeline.sh failed with return code {result.returncode}\n"
        f"stderr: {result.stderr}"
    )
    assert OUTPUT.is_file(), f"Output file not created by pipeline: {OUTPUT}"

    lines = read_output()
    expected_lines = ["4", "2", "5"]
    assert lines == expected_lines, f"Expected {expected_lines}, but got {lines} in {OUTPUT}"


def test_cpp_computation_and_real_pipeline_integration():
    original_cpp = CPP.read_bytes()
    original_artifacts = ARTIFACTS.read_bytes()
    original_metrics = METRICS.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    direct_binary = Path("/tmp/detect_submission")

    try:
        # Compile and exercise the submitted C++ program directly on verifier-derived data.
        compile_result = run([
            "/usr/bin/g++", "-std=c++17", "-O2", str(CPP), "-o", str(direct_binary)
        ])
        assert compile_result.returncode == 0, (
            "detect.cpp did not compile independently:\n" + compile_result.stderr
        )

        ids = sorted(secrets.SystemRandom().sample(range(1000, 9000), 8))
        rng = secrets.SystemRandom()
        while True:
            records = [
                (ids[i], rng.randint(0, 850), rng.randint(1, 999) / 1000.0)
                for i in range(8)
            ]
            distances = []
            for artifact_id, size, error_rate in records:
                posterior = (error_rate * 0.05) / (error_rate * 0.05 + 0.0095)
                distances.append(math.hypot(posterior - 1.0, size / 1000.0))
            if min(abs(a - b) for i, a in enumerate(distances) for b in distances[i + 1:]) > 1e-7:
                break

        direct_input = "".join(f"{i} {s} {e:.3f}\n" for i, s, e in records)
        direct_result = run([str(direct_binary)], input=direct_input)
        assert direct_result.returncode == 0, (
            "Compiled detect.cpp failed on test input:\n" + direct_result.stderr
        )
        direct_lines = [x.strip() for x in direct_result.stdout.splitlines() if x.strip()]
        assert direct_lines == expected_ids(records), (
            f"detect.cpp returned {direct_lines}, expected {expected_ids(records)}"
        )

        # Exercise the submitted pipeline on fresh joined files, including unmatched IDs.
        artifact_rows = [(i, s) for i, s, _ in records]
        metrics_rows = [(i, e) for i, _, e in records]
        artifact_rows.append((95001, 17))       # no corresponding metric
        metrics_rows.append((95002, 0.777))    # no corresponding artifact
        artifact_rows.sort()
        metrics_rows.sort()
        write_rows(ARTIFACTS, artifact_rows)
        write_rows(METRICS, metrics_rows)
        if OUTPUT.exists():
            OUTPUT.unlink()

        pipeline_result = run(["/bin/bash", str(SCRIPT)], cwd=str(HOME))
        assert pipeline_result.returncode == 0, (
            "pipeline.sh failed on generated fixture:\n" + pipeline_result.stderr
        )
        assert read_output() == expected_ids(records), (
            "pipeline output did not match the verifier-derived Bayesian distances"
        )

        # Replace detect.cpp temporarily with a probe. A compliant pipeline must compile this
        # source, feed it the inner join as id/size/error_rate, and redirect its output.
        probe_ids = sorted(secrets.SystemRandom().sample(range(20000, 80000), 3))
        probe_records = [
            (probe_ids[0], 123, 0.314),
            (probe_ids[1], 456, 0.271),
            (probe_ids[2], 789, 0.618),
        ]
        artifact_probe = [(i, s) for i, s, _ in probe_records] + [(99991, 11)]
        metric_probe = [(i, e) for i, _, e in probe_records] + [(99992, 0.5)]
        artifact_probe.sort()
        metric_probe.sort()
        write_rows(ARTIFACTS, artifact_probe)
        write_rows(METRICS, metric_probe)

        magic = secrets.SystemRandom().sample(range(100000, 999999), 3)
        checks = "\n".join(
            f"    if (rows[{n}].id != {i} || rows[{n}].size != {s} || "
            f"std::fabs(rows[{n}].error - {e!r}) > 1e-12) return 12;"
            for n, (i, s, e) in enumerate(probe_records)
        )
        CPP.write_text(f'''#include <cmath>
#include <iostream>
#include <vector>
struct Row {{ long long id; double size; double error; }};
int main() {{
    std::vector<Row> rows;
    Row row;
    while (std::cin >> row.id >> row.size >> row.error) rows.push_back(row);
    if (rows.size() != 3) return 11;
{checks}
    std::cout << {magic[0]} << "\\n" << {magic[1]} << "\\n" << {magic[2]} << "\\n";
    return 0;
}}
''')
        if OUTPUT.exists():
            OUTPUT.unlink()
        probe_result = run(["/bin/bash", str(SCRIPT)], cwd=str(HOME))
        assert probe_result.returncode == 0, (
            "pipeline did not successfully compile and execute detect.cpp on the joined stream:\n"
            + probe_result.stderr
        )
        assert read_output() == [str(x) for x in magic], (
            "pipeline.sh did not compile/execute the current detect.cpp and redirect its output"
        )
    finally:
        CPP.write_bytes(original_cpp)
        ARTIFACTS.write_bytes(original_artifacts)
        METRICS.write_bytes(original_metrics)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)
        if direct_binary.exists():
            direct_binary.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
