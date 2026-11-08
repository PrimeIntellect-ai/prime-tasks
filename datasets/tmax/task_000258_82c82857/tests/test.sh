#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import subprocess
import tempfile
import uuid

import pytest


def run(cmd, timeout=30, cwd=None):
    return subprocess.run(cmd, capture_output=True, timeout=timeout, cwd=cwd)


def test_task1_c_log_processor():
    tool_dir = "/home/user/log_tool"
    executable = os.path.join(tool_dir, "log_processor")
    source = os.path.join(tool_dir, "process_log.c")
    makefile = os.path.join(tool_dir, "Makefile")

    # Preserve the original existence and executability assertions.
    assert os.path.isfile(executable), f"Executable {executable} is missing. Did you compile the C program?"
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."
    assert os.path.isfile(source), f"Source file {source} is missing."
    assert os.path.isfile(makefile), f"Makefile {makefile} is missing."

    initial = run([executable], timeout=10)
    assert initial.returncode == 0, "The compiled log processor did not run successfully."
    assert initial.stdout == b"Log processed.\n", "The log processor does not implement the provided C program."
    assert open(executable, "rb").read(4) == b"\x7fELF", "log_processor is not a compiled ELF executable."

    # Prove that make actually recompiles process_log.c into the requested output,
    # rather than accepting an unrelated executable placed at that path.
    original_source = open(source, "rb").read()
    marker = "make_rebuild_" + uuid.uuid4().hex
    replacement = (
        '#include <stdio.h>\n'
        'int main(void) { puts("' + marker + '"); return 0; }\n'
    ).encode()
    restore_result = None
    try:
        with open(source, "wb") as f:
            f.write(replacement)
        if os.path.lexists(executable):
            os.unlink(executable)

        built = run(["make", "-B"], timeout=30, cwd=tool_dir)
        assert built.returncode == 0, (
            "The Makefile could not rebuild the C program:\n"
            + (built.stdout + built.stderr).decode(errors="replace")
        )
        assert os.path.isfile(executable), "make did not create log_processor."
        assert os.access(executable, os.X_OK), "The rebuilt log_processor is not executable."
        assert open(executable, "rb").read(4) == b"\x7fELF", "The Makefile did not produce a compiled ELF executable."
        rebuilt = run([executable], timeout=10)
        assert rebuilt.returncode == 0
        assert rebuilt.stdout == (marker + "\n").encode(), "The Makefile did not compile the current process_log.c source."
    finally:
        with open(source, "wb") as f:
            f.write(original_source)
        restore_result = run(["make", "-B"], timeout=30, cwd=tool_dir)

    assert restore_result.returncode == 0, "The original log processor could not be restored by make."
    restored = run([executable], timeout=10)
    assert restored.returncode == 0 and restored.stdout == b"Log processed.\n"


def test_task2_go_sanitizer():
    sanitizer_path = "/home/user/sanitizer.go"
    assert os.path.isfile(sanitizer_path), f"Go sanitizer not found at {sanitizer_path}"

    # Preserve the original fixed-corpus checks.
    evil_files = glob.glob("/app/corpus/evil/*")
    clean_files = glob.glob("/app/corpus/clean/*")
    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    clean_rejected = []
    for path in evil_files:
        res = run(["go", "run", sanitizer_path, path], timeout=45)
        if res.returncode == 0:
            evil_bypassed.append(os.path.basename(path))
    for path in clean_files:
        res = run(["go", "run", sanitizer_path, path], timeout=45)
        if res.returncode != 0:
            clean_rejected.append(os.path.basename(path))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")
    if errors:
        pytest.fail(" | ".join(errors))

    with tempfile.TemporaryDirectory(prefix="sanitizer_verify_") as td:
        binary = os.path.join(td, uuid.uuid4().hex)
        compiled = run(["go", "build", "-o", binary, sanitizer_path], timeout=60)
        assert compiled.returncode == 0, "sanitizer.go does not compile:\n" + (compiled.stdout + compiled.stderr).decode(errors="replace")

        for args in ([], ["one", "two"]):
            res = run([binary] + args, timeout=10)
            assert res.returncode != 0, "The sanitizer must require exactly one file path argument."

        cases = [
            b"",
            b"ordinary ASCII log",
            b"tabs\tare\tallowed\r\nnew lines too\n",
            "Unicode: café, 東京, 🙂\n".encode("utf-8"),
            b"A" * 2000,
            b"A" * 1999 + b"\r",
            b"A" * 2000 + b"\n" + b"B" * 2000,
            b"A" * 2001,
            b"ok\n" + b"B" * 2001 + b"\n",
            b"invalid \xff byte",
            b"truncated \xe2\x82",
            b"overlong \xc0\xaf",
            b"surrogate \xed\xa0\x80",
        ]

        # Exercise every forbidden ASCII control independently.
        for value in list(range(0x20)) + [0x7F]:
            if value not in (0x09, 0x0A, 0x0D):
                cases.append(b"prefix" + bytes([value]) + b"suffix")

        # Add runtime-generated cases at unpredictable paths so pathname or
        # fixture hardcoding cannot satisfy the behavioral contract.
        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        alphabet = ["a", "Z", "9", "é", "λ", "界", "🙂", " ", "\t", "\r"]
        for _ in range(18):
            lines = []
            for _ in range(rng.randint(1, 5)):
                text = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 120)))
                while len(text.encode("utf-8")) > 2000:
                    text = text[:-1]
                lines.append(text)
            cases.append("\n".join(lines).encode("utf-8"))

        for _ in range(12):
            kind = rng.randrange(3)
            if kind == 0:
                bad = rng.choice([b"\xff", b"\xfe", b"\xc0\x80", b"\xf5\x80\x80\x80", b"\xe2\x82"])
                cases.append(os.urandom(rng.randint(0, 8)).hex().encode() + bad + b"tail")
            elif kind == 1:
                forbidden = rng.choice([x for x in list(range(0x20)) + [0x7F] if x not in (9, 10, 13)])
                cases.append(os.urandom(8).hex().encode() + bytes([forbidden]) + b"tail")
            else:
                cases.append(b"x\n" + os.urandom(1001).hex().encode() + b"z")

        def oracle(data):
            try:
                data.decode("utf-8", errors="strict")
            except UnicodeDecodeError:
                return False
            if any((byte < 0x20 or byte == 0x7F) and byte not in (0x09, 0x0A, 0x0D) for byte in data):
                return False
            return all(len(line) <= 2000 for line in data.split(b"\n"))

        rng.shuffle(cases)
        for data in cases:
            path = os.path.join(td, uuid.uuid4().hex)
            with open(path, "wb") as f:
                f.write(data)
            expected_accept = oracle(data)
            res = run([binary, path], timeout=10)
            if expected_accept:
                assert res.returncode == 0, f"Sanitizer rejected a valid generated input at {path}."
            else:
                assert res.returncode == 1, f"Sanitizer failed to reject an invalid generated input with status 1 at {path}."
                assert res.stdout or res.stderr, "The sanitizer must print an error when rejecting a file."


def test_task3_video_analysis():
    output_file = "/home/user/red_frame.txt"
    assert os.path.isfile(output_file), f"File {output_file} is missing. Did you run the video analysis?"
    with open(output_file, "r") as f:
        content = f.read().strip()
    assert content == "142", f"Expected red frame index 142, but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
