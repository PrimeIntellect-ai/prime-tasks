#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

if [[ ! -f /home/user/fix_project.py || -L /home/user/fix_project.py ]]; then
    exit 0
fi

if ! python3 <<'PREP_EOF'
import binascii
import json
import os
import secrets

project = "/home/user/rust_proj"
os.makedirs(project + "/src", exist_ok=True)

original = """pub fn add(a: i32, b: i32) -> i32 {
    a - b // BUG: Should be addition
}

pub fn multiply(a: i32, b: i32) -> i32 {
    a / b // BUG: Should be multiplication
}
"""
marker = "PATCH_MARKER_" + secrets.token_hex(8)
expected = f"""pub fn add(a: i32, b: i32) -> i32 {{
    a + b
}}

pub fn multiply(a: i32, b: i32) -> i32 {{
    a * b
}}
// {marker}
"""
diff_text = f"""--- src/math_ops.rs
+++ src/math_ops.rs
@@ -1,7 +1,8 @@
 pub fn add(a: i32, b: i32) -> i32 {{
-    a - b // BUG: Should be addition
+    a + b
 }}

 pub fn multiply(a: i32, b: i32) -> i32 {{
-    a / b // BUG: Should be multiplication
+    a * b
 }}
+// {marker}
"""

with open(project + "/src/math_ops.rs", "w") as f:
    f.write(original)
with open("/home/user/encoded_patch.txt", "w") as f:
    for line in diff_text.splitlines(keepends=True):
        f.write("ENC: " + binascii.hexlify(line.encode()).decode() + "\n")
with open("/tmp/expected_math_ops.rs", "w") as f:
    f.write(expected)

for path in (project + "/src/constants.rs", "/home/user/benchmark.json"):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

log_path = "/tmp/mock_rust_invocations.jsonl"
with open(log_path, "w"):
    pass
os.chmod(log_path, 0o666)

delays = {
    "10": 0.040 + secrets.randbelow(31) / 1000.0,
    "100": 0.110 + secrets.randbelow(61) / 1000.0,
    "1000": 0.260 + secrets.randbelow(121) / 1000.0,
}
mock = f'''import json
import sys
import time

DELAYS = {delays!r}
LOG = {log_path!r}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in DELAYS:
        sys.exit(1)
    arg = sys.argv[1]
    start = time.monotonic()
    time.sleep(DELAYS[arg])
    elapsed = time.monotonic() - start
    with open(LOG, "a") as f:
        f.write(json.dumps({{"arg": arg, "elapsed": elapsed}}) + "\\n")
'''
with open(project + "/mock_rust_binary.py", "w") as f:
    f.write(mock)
os.chmod(project + "/mock_rust_binary.py", 0o755)
PREP_EOF
then
    exit 0
fi

if ! cd /home/user && timeout 20s python3 /home/user/fix_project.py; then
    exit 0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pytest


def test_fix_script_exists_and_is_python():
    path = "/home/user/fix_project.py"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert not os.path.islink(path), f"File {path} must be a regular script, not a symlink."
    with open(path, "rb") as f:
        source = f.read()
    compile(source, path, "exec")


def test_math_ops_patched():
    math_ops_path = "/home/user/rust_proj/src/math_ops.rs"
    assert os.path.isfile(math_ops_path), f"File {math_ops_path} does not exist."

    with open(math_ops_path, "r") as f:
        content = f.read()

    assert "a + b" in content, "math_ops.rs does not contain the fixed 'a + b' logic."
    assert "a * b" in content, "math_ops.rs does not contain the fixed 'a * b' logic."
    assert "BUG" not in content, "math_ops.rs still contains the original buggy comments."
    assert "a - b" not in content, "math_ops.rs still contains the original subtraction bug."
    assert "a / b" not in content, "math_ops.rs still contains the original division bug."

    with open("/tmp/expected_math_ops.rs", "r") as f:
        expected = f.read()
    assert content == expected, "math_ops.rs is not the result of decoding and applying the supplied patch."


def test_constants_rs_generated():
    constants_path = "/home/user/rust_proj/src/constants.rs"
    assert os.path.isfile(constants_path), f"File {constants_path} does not exist."

    with open(constants_path, "r") as f:
        content = f.read()

    assert "pub const PRIMES: [u32; 100] =" in content, "constants.rs does not contain the expected variable definition 'pub const PRIMES: [u32; 100] ='."

    try:
        array_content = content.split("=")[1].strip().strip(";").strip("[]")
        numbers = [int(x.strip()) for x in array_content.split(",") if x.strip()]
    except Exception as e:
        pytest.fail(f"Failed to parse the array of primes in constants.rs: {e}")

    expected_primes = []
    num = 2
    while len(expected_primes) < 100:
        is_prime = True
        for p in expected_primes:
            if p * p > num:
                break
            if num % p == 0:
                is_prime = False
                break
        if is_prime:
            expected_primes.append(num)
        num += 1

    assert len(numbers) == 100, f"Expected exactly 100 primes, but found {len(numbers)}."
    assert numbers == expected_primes, "The array in constants.rs does not match the first 100 prime numbers."


def test_benchmark_json_generated():
    bench_path = "/home/user/benchmark.json"
    assert os.path.isfile(bench_path), f"File {bench_path} does not exist."

    with open(bench_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("benchmark.json does not contain valid JSON.")

    expected_keys = ["10", "100", "1000"]
    assert set(data) == set(expected_keys), "benchmark.json must contain exactly the required keys."
    for key in expected_keys:
        assert key in data, f"Key '{key}' is missing from benchmark.json."
        assert isinstance(data[key], float), f"Value for key '{key}' is not a float (got {type(data[key]).__name__})."
        assert data[key] >= 0.0, f"Value for key '{key}' is negative, which is invalid for execution time."

    records = []
    with open("/tmp/mock_rust_invocations.jsonl", "r") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))

    for key in expected_keys:
        matching = [r for r in records if r.get("arg") == key]
        assert matching, f"The replica was not executed for input {key}."
        measured_inside_replica = min(float(r["elapsed"]) for r in matching)
        reported = data[key]
        assert reported >= measured_inside_replica * 0.8, f"Reported time for {key} is too small to be a wall-clock measurement."
        assert reported <= measured_inside_replica + 1.0, f"Reported time for {key} is not consistent with the executed benchmark."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
