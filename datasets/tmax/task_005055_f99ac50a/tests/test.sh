#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import struct
import subprocess
import tempfile
import time


def fletcher32(data):
    sum1 = 0xffff
    sum2 = 0xffff
    for i in range(0, len(data), 2):
        word = data[i]
        if i + 1 < len(data):
            word |= data[i + 1] << 8
        sum1 = (sum1 + word) % 65535
        sum2 = (sum2 + sum1) % 65535
    return (sum2 << 16) | sum1


def expected_archive(root):
    files = []
    for base, _, names in os.walk(root):
        for name in names:
            full = os.path.join(base, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            files.append((rel, full))
    files.sort(key=lambda item: item[0])

    result = bytearray(b"PAK1")
    result += struct.pack("<I", len(files))
    for rel, full in files:
        with open(full, "rb") as f:
            data = f.read()
        path = rel.encode()
        result += struct.pack("<H", len(path))
        result += path
        result += struct.pack("<I", len(data))
        result += struct.pack("<I", fletcher32(data))
        result += data
    return bytes(result)


def build_go_packer():
    go_src = "/workspace/fast_packer.go"
    assert os.path.isfile(go_src), f"Go source file not found at {go_src}"
    go_bin = "/tmp/fast_packer"
    compile_res = subprocess.run(
        ["go", "build", "-o", go_bin, go_src], capture_output=True, text=True
    )
    assert compile_res.returncode == 0, f"Go compilation failed:\n{compile_res.stderr}"
    assert os.path.isfile(go_bin), "Go binary was not created after successful compilation."
    return go_bin


def test_validator_compiled_and_functional():
    """Rebuild through the repaired Makefile and exercise the resulting validator."""
    src_dir = "/workspace/validator_src"
    makefile = os.path.join(src_dir, "Makefile")
    validator_path = os.path.join(src_dir, "validator")
    assert os.path.isfile(makefile), f"Makefile not found at {makefile}"

    if os.path.lexists(validator_path):
        os.unlink(validator_path)
    build = subprocess.run(
        ["make", "-B", "validator"], cwd=src_dir, capture_output=True, text=True
    )
    assert build.returncode == 0, f"Rebuilding validator through Makefile failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(validator_path), f"Validator executable not found at {validator_path}. Did you fix the Makefile and build it?"
    assert os.access(validator_path, os.X_OK), f"File at {validator_path} is not executable."

    with tempfile.TemporaryDirectory() as tmpdir:
        valid = os.path.join(tmpdir, secrets.token_hex(8) + ".pak")
        invalid = os.path.join(tmpdir, secrets.token_hex(8) + ".pak")
        with open(valid, "wb") as f:
            f.write(b"PAK1" + struct.pack("<I", 0))
        with open(invalid, "wb") as f:
            f.write(b"BAD!" + struct.pack("<I", 0))

        assert subprocess.run([validator_path, valid]).returncode == 0, "Validator rejected a valid PAK1 archive."
        assert subprocess.run([validator_path, invalid]).returncode != 0, "Validator accepted an archive with invalid magic."
        assert subprocess.run([validator_path]).returncode != 0, "Validator accepted a missing archive argument."


def test_go_packer_independent_correctness():
    """Check randomized archives against an independently derived PAK1 result."""
    go_bin = build_go_packer()
    with tempfile.TemporaryDirectory() as tmpdir:
        dataset = os.path.join(tmpdir, secrets.token_hex(8))
        os.makedirs(os.path.join(dataset, "nested", "empty"))
        samples = {
            "z.bin": os.urandom(513),
            "a.txt": b"",
            "nested/odd.dat": os.urandom(1001),
            "nested/even.dat": os.urandom(2048),
        }
        for rel, data in samples.items():
            path = os.path.join(dataset, *rel.split("/"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)

        expected = expected_archive(dataset)
        output = os.path.join(tmpdir, secrets.token_hex(8) + ".pak")
        result = subprocess.run([go_bin, dataset, output], capture_output=True, text=True)
        assert result.returncode == 0, f"Go packer failed on randomized input:\n{result.stderr}"
        assert os.path.isfile(output), "Go packer did not create the requested archive."
        with open(output, "rb") as f:
            actual = f.read()
        assert actual == expected, "Go packer output did not match the independently derived PAK1 archive."


def test_go_packer_speedup_and_correctness():
    """Run against a large dataset, compare with the oracle, and verify speedup."""
    go_bin = build_go_packer()
    oracle_bin = "/app/packer_oracle"
    assert os.path.isfile(oracle_bin), f"Oracle binary missing at {oracle_bin}"

    with tempfile.TemporaryDirectory() as tmpdir:
        dataset_dir = os.path.join(tmpdir, "dataset")
        os.makedirs(dataset_dir)
        for i in range(10):
            os.makedirs(os.path.join(dataset_dir, f"dir_{i}"))

        chunk = os.urandom(50 * 1024)
        for i in range(10000):
            path = os.path.join(dataset_dir, f"dir_{i % 10}", f"file_{i}.bin")
            with open(path, "wb") as f:
                f.write(i.to_bytes(4, "little") + chunk[4:])

        # Create the oracle result in a private, separate location. Hash it and
        # remove it completely before the submitted program is started.
        oracle_dir = tempfile.mkdtemp(prefix="reference-", dir=tmpdir)
        oracle_out = os.path.join(oracle_dir, secrets.token_hex(16) + ".pak")
        start_oracle = time.time()
        oracle_res = subprocess.run(
            [oracle_bin, dataset_dir, oracle_out], capture_output=True, text=True
        )
        time_oracle = time.time() - start_oracle
        assert oracle_res.returncode == 0, f"Oracle failed to run:\n{oracle_res.stderr}"
        assert os.path.isfile(oracle_out), "Oracle failed to produce the output archive."

        def get_sha256(path):
            h = hashlib.sha256()
            with open(path, "rb") as f:
                for block in iter(lambda: f.read(65536), b""):
                    h.update(block)
            return h.hexdigest()

        oracle_hash = get_sha256(oracle_out)
        os.unlink(oracle_out)
        os.rmdir(oracle_dir)
        assert not os.path.exists(oracle_out)

        go_dir = tempfile.mkdtemp(prefix="submission-", dir=tmpdir)
        go_out = os.path.join(go_dir, secrets.token_hex(16) + ".pak")
        start_go = time.time()
        go_res = subprocess.run(
            [go_bin, dataset_dir, go_out], capture_output=True, text=True
        )
        time_go = time.time() - start_go
        assert go_res.returncode == 0, f"Go packer failed to run:\n{go_res.stderr}"
        assert os.path.isfile(go_out), "Go packer failed to produce the output archive."

        go_hash = get_sha256(go_out)
        assert oracle_hash == go_hash, (
            "Output mismatch! The Go packer output does not match the Oracle output.\n"
            f"Oracle SHA256: {oracle_hash}\nGo SHA256:     {go_hash}"
        )

        speedup = time_oracle / time_go
        assert speedup >= 2.5, (
            f"Performance metric failed: Speedup is {speedup:.2f}x "
            f"(Oracle: {time_oracle:.2f}s, Go: {time_go:.2f}s). "
            "Required speedup is >= 2.5x. Ensure you are using concurrency effectively."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
