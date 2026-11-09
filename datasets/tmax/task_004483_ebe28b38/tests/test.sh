#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

cat << 'INDEPENDENT_EOF' > /tmp/independent_verify.py
import importlib.util
import os
import random
import stat
import string
import time
import unicodedata

MODULE_PATH = "/app/authproxy/normalize.py"

assert os.path.exists(MODULE_PATH), f"Missing required artifact: {MODULE_PATH}"
assert not os.path.islink(MODULE_PATH), f"Artifact must not be a symlink: {MODULE_PATH}"
assert stat.S_ISREG(os.stat(MODULE_PATH).st_mode), f"Artifact is not a regular file: {MODULE_PATH}"

spec = importlib.util.spec_from_file_location("candidate_normalize", MODULE_PATH)
assert spec is not None and spec.loader is not None, "Could not load normalize.py"
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
canonicalize_request = getattr(module, "canonicalize_request", None)
assert callable(canonicalize_request), "canonicalize_request is missing or not callable"


def decode_like_original(value):
    # All generated percent escapes are valid. Decode one URL-escape layer at a
    # time, matching the original function's repeated decoding behavior.
    while "%" in value:
        output = []
        i = 0
        while i < len(value):
            if value[i] == "%":
                assert i + 2 < len(value)
                output.append(chr(int(value[i + 1:i + 3], 16)))
                i += 3
            else:
                output.append(value[i])
                i += 1
        value = "".join(output)
    return value


def oracle(path, query):
    normalized = unicodedata.normalize("NFKC", decode_like_original(path))
    if not query:
        return normalized
    return normalized + "?" + "&".join(sorted(query.split("&")))


# Preserve the specified examples independently of the editable test file.
fixed_cases = [
    ("/api/%20test", "b=2&a=1"),
    ("/api/%20test", ""),
    ("/api/\u212B", ""),
    ("/%252Fadmin/%2541", "z=9&a=2&a=1"),
    ("/fullwidth/\uff21\uff22\uff23", "x=1"),
]
for path, query in fixed_cases:
    actual = canonicalize_request(path, query)
    expected = oracle(path, query)
    assert actual == expected, (path, query, expected, actual)


# Exercise fresh, unpredictable valid inputs so the three public examples cannot
# simply be hardcoded.
rng = random.SystemRandom()
literals = string.ascii_letters + string.digits + "/_-~."
unicode_literals = ["\u212b", "\uff21", "\ufb01", "\u00e9", "\u2163"]
encoded_values = [0x20, 0x2F, 0x2B, 0x3D, 0x41, 0x61, 0x7E, 0xC5]

for _ in range(100):
    pieces = ["/"]
    for _ in range(rng.randint(8, 35)):
        kind = rng.randrange(4)
        if kind == 0:
            pieces.append(rng.choice(literals))
        elif kind == 1:
            pieces.append("%%%02X" % rng.choice(encoded_values))
        elif kind == 2:
            # %25XX becomes %XX and is then decoded on the next pass.
            pieces.append("%25%02X" % rng.choice(encoded_values))
        else:
            pieces.append(rng.choice(unicode_literals))
    path = "".join(pieces)

    if rng.randrange(5) == 0:
        query = ""
    else:
        params = []
        for _ in range(rng.randint(1, 30)):
            key = "".join(rng.choice(string.ascii_letters) for _ in range(rng.randint(1, 8)))
            value = "".join(rng.choice(string.ascii_letters + string.digits + "_-%") for _ in range(rng.randint(0, 8)))
            params.append(key + "=" + value)
        rng.shuffle(params)
        query = "&".join(params)

    actual = canonicalize_request(path, query)
    expected = oracle(path, query)
    assert actual == expected, (path, query, expected, actual)


# Recreate the required benchmark internally rather than trusting benchmark.py's
# reported number. Validate its result as well as its elapsed time.
benchmark_path = "/api/v1/resource/" + "%20".join(["test"] * 1000)
benchmark_query = "&".join([f"k{i}=v{i}" for i in range(1000, 0, -1)])
benchmark_expected = oracle(benchmark_path, benchmark_query)
start = time.perf_counter()
benchmark_actual = canonicalize_request(benchmark_path, benchmark_query)
elapsed = time.perf_counter() - start
assert benchmark_actual == benchmark_expected, "Incorrect result on benchmark-sized input"
assert elapsed < 0.1, f"Independent benchmark took {elapsed:.6f}s, expected below 0.1s"

# Also use a fresh large ordering so optimizing only the published benchmark
# input cannot satisfy the performance requirement.
params = []
for i in range(1000):
    key = "".join(rng.choice(string.ascii_letters) for _ in range(12))
    params.append(f"{key}{i}=v{i}")
rng.shuffle(params)
random_query = "&".join(params)
random_path = "/random/" + "%20".join(
    "".join(rng.choice(string.ascii_letters) for _ in range(4)) for _ in range(1000)
)
random_expected = oracle(random_path, random_query)
start = time.perf_counter()
random_actual = canonicalize_request(random_path, random_query)
random_elapsed = time.perf_counter() - start
assert random_actual == random_expected, "Incorrect result on randomized benchmark-sized input"
assert random_elapsed < 0.1, f"Randomized benchmark took {random_elapsed:.6f}s, expected below 0.1s"
INDEPENDENT_EOF

python3 -I /tmp/independent_verify.py || status=1

# Retain the original verifier's assertions in addition to the independent checks.
cat << 'TEST_EOF' > /tmp/test_final_state.py
import subprocess
import os
import sys

def test_functional_correctness():
    """Verify that the functional tests still pass perfectly."""
    test_path = "/app/authproxy/tests/test_normalize.py"
    assert os.path.isfile(test_path), f"Test file {test_path} is missing."

    result = subprocess.run(
        [sys.executable, "-m", "pytest", test_path],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Functional tests failed:\n{result.stdout}\n{result.stderr}"

def test_benchmark_performance():
    """Verify that the benchmark runs in <= 0.1 seconds."""
    benchmark_path = "/app/authproxy/benchmark.py"
    assert os.path.isfile(benchmark_path), f"Benchmark file {benchmark_path} is missing."

    result = subprocess.run(
        [sys.executable, benchmark_path],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Benchmark script failed to run:\n{result.stderr}"

    output = result.stdout.strip()
    try:
        runtime = float(output)
    except ValueError:
        assert False, f"Benchmark output is not a valid float: {output}"

    threshold = 0.1
    assert runtime <= threshold, f"Performance regression: benchmark took {runtime:.6f}s, which is > {threshold}s threshold."
TEST_EOF

PYTHONPATH=/app:${PYTHONPATH} python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
