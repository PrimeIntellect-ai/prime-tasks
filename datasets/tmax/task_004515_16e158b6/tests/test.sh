#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import tempfile

BASE_DIR = "/home/user/malware_analysis"

def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=BASE_DIR, capture_output=True, text=True, **kwargs)

def test_requirements_fixed_and_installable():
    req = os.path.join(BASE_DIR, "requirements.txt")
    assert os.path.isfile(req), f"{req} is missing."
    with open(req) as f:
        content = f.read()
    if "requests==2.26.0" in content:
        assert "urllib3==1.20" not in content, "requirements.txt still contains conflicting urllib3==1.20"
    with tempfile.TemporaryDirectory() as target:
        result = subprocess.run(
            ["python3", "-m", "pip", "install", "--disable-pip-version-check", "--no-input", "--target", target, "-r", req],
            cwd=BASE_DIR, capture_output=True, text=True, timeout=180)
        assert result.returncode == 0, f"requirements do not install successfully:\n{result.stdout}\n{result.stderr}"

def test_parser_behavior_on_zero_length_and_following_records():
    parser = os.path.join(BASE_DIR, "parser.py")
    assert os.path.isfile(parser), f"{parser} is missing."
    with tempfile.NamedTemporaryFile(dir=BASE_DIR, suffix=".bin", delete=False) as f:
        path = f.name
        # Zero-length records of handled message types must be skipped, and parsing must continue.
        f.write(struct.pack(">BH", 1, 0))
        f.write(struct.pack(">BH", 1, 1) + b"\x07")
        f.write(struct.pack(">BH", 2, 0))
        f.write(struct.pack(">BH", 2, 1) + b"\x0b")
    try:
        result = run(["python3", parser, path])
        assert result.returncode == 0, f"parser crashed on zero-length TLV:\n{result.stderr}"
        assert result.stdout.splitlines() == ["7", "22"], f"parser did not skip zero-length TLVs and continue: {result.stdout!r}"
    finally:
        os.unlink(path)

def test_cluster_behavior_with_empty_cluster():
    source = os.path.join(BASE_DIR, "cluster_beacons.c")
    assert os.path.isfile(source), f"{source} is missing."
    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "cluster")
        build = subprocess.run(["gcc", "-o", binary, source, "-lm"], capture_output=True, text=True)
        assert build.returncode == 0, f"cluster_beacons.c does not compile:\n{build.stderr}"
        data = os.path.join(td, "one_cluster.txt")
        with open(data, "w") as f:
            f.write("12\n14\n13\n")
        result = subprocess.run([binary, data], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"cluster program failed: {result.stderr}"
        assert result.stdout.splitlines() == ["Centroids:", "13.00", "50.00"], \
            f"empty cluster centroid was not kept unchanged: {result.stdout!r}"

def test_regression_test_sh_actually_builds_edge_file_and_runs_parser():
    script = os.path.join(BASE_DIR, "regression_test.sh")
    assert os.path.isfile(script), f"{script} is missing."
    assert os.access(script, os.X_OK), f"{script} is not executable."
    edge = os.path.join(BASE_DIR, "test_edge.bin")
    if os.path.exists(edge):
        os.unlink(edge)
    result = run([script])
    assert result.returncode == 0, f"regression_test.sh failed with exit code {result.returncode}:\n{result.stdout}\n{result.stderr}"
    assert result.stdout == "REGRESSION TEST PASSED\n", f"unexpected regression output: {result.stdout!r}"
    assert os.path.isfile(edge), "regression_test.sh did not create test_edge.bin"
    raw = open(edge, "rb").read()
    pos = 0
    saw_zero = False
    while pos + 3 <= len(raw):
        _, length = struct.unpack(">BH", raw[pos:pos+3])
        pos += 3
        assert pos + length <= len(raw), "test_edge.bin contains a truncated TLV"
        saw_zero |= length == 0
        pos += length
    assert pos == len(raw) and saw_zero, "test_edge.bin does not explicitly contain a valid zero-length TLV"

def test_full_pipeline_from_real_inputs():
    parser = os.path.join(BASE_DIR, "parser.py")
    source = os.path.join(BASE_DIR, "cluster_beacons.c")
    log = os.path.join(BASE_DIR, "suspicious_log.bin")
    for path in (parser, source, log):
        assert os.path.isfile(path), f"{path} is missing."
    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "cluster_beacons")
        intervals = os.path.join(td, "intervals.txt")
        build = subprocess.run(["gcc", "-o", binary, source, "-lm"], capture_output=True, text=True)
        assert build.returncode == 0, f"compile failed:\n{build.stderr}"
        parsed = run(["python3", parser, log])
        assert parsed.returncode == 0, f"parser failed on suspicious_log.bin:\n{parsed.stderr}"
        assert parsed.stdout.splitlines() == ["12", "14", "13", "50", "52"], f"incorrect parsed intervals: {parsed.stdout!r}"
        with open(intervals, "w") as f:
            f.write(parsed.stdout)
        clustered = subprocess.run([binary, intervals], capture_output=True, text=True, timeout=10)
        assert clustered.returncode == 0, f"clustering failed:\n{clustered.stderr}"
        expected = ["Centroids:", "13.00", "51.00"]
        assert clustered.stdout.splitlines() == expected, f"incorrect pipeline output: {clustered.stdout!r}"

    final_path = os.path.join(BASE_DIR, "final_beacons.txt")
    assert os.path.isfile(final_path), f"{final_path} is missing. Did you run the pipeline?"
    with open(final_path) as f:
        assert f.read().splitlines() == expected, "final_beacons.txt does not contain the required pipeline result"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
