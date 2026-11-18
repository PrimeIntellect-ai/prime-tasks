#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import struct
import subprocess
import tempfile
import pytest

SANITISER = "/home/user/sanitiser"
SOURCE = "/home/user/sanitiser.cpp"


def run_tool(tool, archive):
    try:
        return subprocess.run(
            [tool, archive],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitiser timed out on {archive}")


def encode_xar2(entries):
    out = bytearray(b"XAR2")
    out += struct.pack("<I", len(entries))
    for etype, path, data in entries:
        path_b = path.encode("ascii")
        out += struct.pack("<BH", etype, len(path_b))
        out += path_b
        if etype == 2:
            out += struct.pack("<Q", 0)
        elif etype == 1:
            data_b = data.encode("ascii")
            out += struct.pack("<Q", len(data_b))
            out += data_b
        else:
            data_b = bytes(data)
            out += struct.pack("<Q", len(data_b))
            out += data_b
    return bytes(out)


def opaque_name():
    return secrets.token_hex(16) + ".xar2"


def test_sanitiser_exists_and_executable():
    sanitiser_path = "/home/user/sanitiser"
    assert os.path.exists(sanitiser_path), f"Sanitiser executable not found at {sanitiser_path}"
    assert os.path.isfile(sanitiser_path), f"{sanitiser_path} is not a file"
    assert os.access(sanitiser_path, os.X_OK), f"Sanitiser at {sanitiser_path} is not executable"


def test_cpp_source_and_compiled_artifact():
    assert os.path.exists(SOURCE), f"C++ source not found at {SOURCE}"
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file"
    with open(SANITISER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Final sanitiser is not a compiled ELF executable"


@pytest.fixture(scope="session")
def rebuilt_sanitiser(tmp_path_factory):
    output = str(tmp_path_factory.mktemp("build") / "sanitiser")
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "sanitiser.cpp does not compile as C++:\n" + result.stderr.decode(errors="replace")
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


def test_adversarial_corpus():
    sanitiser_path = "/home/user/sanitiser"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.xar2')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.xar2')]

    assert len(clean_files) > 0, "No clean corpus files found to test."
    assert len(evil_files) > 0, "No evil corpus files found to test."

    clean_rejected = []
    evil_bypassed = []

    for cf in clean_files:
        result = subprocess.run([sanitiser_path, cf], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(cf))

    for ef in evil_files:
        result = subprocess.run([sanitiser_path, ef], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")

    assert not errors, " | ".join(errors)


def test_generated_archives_at_opaque_paths(rebuilt_sanitiser):
    token = lambda: "n" + secrets.token_hex(5)
    root = token()
    target = token()

    cases = []
    cases.append((encode_xar2([
        (2, root, b""),
        (0, root + "/" + target, secrets.token_bytes(19)),
        (0, root + "/sub/../other", secrets.token_bytes(7)),
        (1, root + "/link", "../" + target),
    ]), 0))
    cases.append((encode_xar2([(0, "/" + token(), b"x")]), 1))
    cases.append((encode_xar2([(2, root + "/../../" + token(), b"")]), 1))
    cases.append((encode_xar2([(1, token(), "/" + token())]), 1))
    cases.append((encode_xar2([(1, root + "/link", "../../" + token())]), 1))

    a, b = token(), token()
    cases.append((encode_xar2([(1, a, b), (1, b, a)]), 1))

    chain5 = [token() for _ in range(5)]
    cases.append((encode_xar2([
        (1, chain5[i], chain5[i + 1] if i + 1 < len(chain5) else target)
        for i in range(len(chain5))
    ] + [(0, target, b"ok")]), 0))

    chain6 = [token() for _ in range(6)]
    cases.append((encode_xar2([
        (1, chain6[i], chain6[i + 1] if i + 1 < len(chain6) else target)
        for i in range(len(chain6))
    ] + [(0, target, b"ok")]), 1))

    valid = encode_xar2([(0, token(), secrets.token_bytes(11))])
    cases.extend([
        (b"", 1),
        (b"BAD!" + struct.pack("<I", 0), 1),
        (b"XAR2" + struct.pack("<I", 1), 1),
        (valid[:-1], 1),
        (b"XAR2" + struct.pack("<I", 1) + struct.pack("<BH", 9, 1) + b"x" + struct.pack("<Q", 0), 1),
        (b"XAR2" + struct.pack("<I", 0) + b"trailing", 1),
    ])

    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="x2check_") as directory:
        written = []
        for content, expected in cases:
            path = os.path.join(directory, opaque_name())
            with open(path, "wb") as f:
                f.write(content)
            written.append((path, expected))

        for tool in (SANITISER, rebuilt_sanitiser):
            for path, expected in written:
                actual = run_tool(tool, path)
                assert actual == expected, (
                    f"{tool} returned {actual}, expected {expected}, "
                    f"for a generated archive at an opaque path"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
