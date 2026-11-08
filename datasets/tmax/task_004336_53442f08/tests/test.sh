#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, **kwargs)


def test_makefile_fixed_and_compiles():
    log_tool_dir = "/home/user/log_tool"
    parser_path = os.path.join(log_tool_dir, "parser")
    assert os.path.isdir(log_tool_dir), f"Directory {log_tool_dir} is missing."

    clean = run(["make", "clean"], cwd=log_tool_dir, text=True, timeout=20)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stderr}\n{clean.stdout}"
    assert not os.path.exists(parser_path), "make clean did not remove parser"

    result = run(["make"], cwd=log_tool_dir, text=True, timeout=30)
    assert result.returncode == 0, f"make failed with output:\n{result.stderr}\n{result.stdout}"
    assert os.path.isfile(parser_path), f"Compiled binary {parser_path} is missing."
    assert os.access(parser_path, os.X_OK), f"Compiled binary {parser_path} is not executable."

    with open(parser_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "parser is not a compiled ELF binary"

    for obj in ("main.o", "log_utils.o"):
        obj_path = os.path.join(log_tool_dir, obj)
        assert os.path.isfile(obj_path), f"Expected compiled object {obj} is missing"
        with open(obj_path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{obj} is not an ELF object"

    dynamic = run(["readelf", "-d", parser_path], text=True, timeout=10)
    assert dynamic.returncode == 0, dynamic.stderr
    assert "libcrypto.so" in dynamic.stdout, "parser is not dynamically linked with libcrypto"

    main_symbols = run(["nm", "-C", os.path.join(log_tool_dir, "main.o")], text=True, timeout=10)
    utils_symbols = run(["nm", "-C", os.path.join(log_tool_dir, "log_utils.o")], text=True, timeout=10)
    assert main_symbols.returncode == 0 and utils_symbols.returncode == 0
    assert " main" in main_symbols.stdout
    assert "parse_line(std::" in main_symbols.stdout
    assert "HashCheck(char const*)" in main_symbols.stdout
    assert "HashCheck(char const*)" in utils_symbols.stdout
    assert "EVP_md5" in utils_symbols.stdout
    assert "EVP_DigestInit_ex" in utils_symbols.stdout

    with tempfile.NamedTemporaryFile("wb", delete=False) as f:
        f.write(b'INFO: generated safe line\nDEBUG: User "test" logged in\n')
        safe_path = f.name
    try:
        executed = run([parser_path, safe_path], timeout=5)
        assert executed.returncode == 0, "compiled parser does not process a safe log successfully"
    finally:
        os.unlink(safe_path)


def test_filter_script_exists():
    filter_path = "/home/user/filter.py"
    assert os.path.isfile(filter_path), f"Filter script missing at {filter_path}"


def parser_safe(line):
    """Model the bounds-relevant behavior of parse_line for one newline-free line."""
    i = 0
    while i < len(line):
        if line[i] == '"':
            i += 1
            while i < len(line) and line[i] != '"':
                if line[i] == "\\":
                    if i == len(line) - 1:
                        return False
                    i += 1
                i += 1
        if i < len(line):
            i += 1
    return True


def invoke_filter(filter_path, path):
    result = run(["python3", filter_path, path], timeout=10)
    assert result.returncode == 0, (
        f"filter exited with {result.returncode}; stderr={result.stderr!r}"
    )
    assert result.stderr == b"", f"filter printed extraneous diagnostics: {result.stderr!r}"
    return result.stdout


def test_generated_hidden_corpora_filtering():
    filter_path = "/home/user/filter.py"
    assert os.path.isfile(filter_path), f"Filter script missing at {filter_path}"

    rng = random.SystemRandom()
    nonce = secrets.token_hex(12)
    ordinary = string.ascii_letters + string.digits + " _-:./=[]{}(),!@#$%^&*"
    random_chars = ordinary + '\\"'

    clean_lines = [
        "",
        f"INFO {nonce}: normal line",
        f'DEBUG {nonce}: User "test" logged in',
        f'WARN {nonce}: Path is "C:\\\\Windows\\\\System32"',
        f'INFO {nonce}: unterminated "quote without a terminal slash',
        f"INFO {nonce}: terminal slash outside a quote\\",
        f'INFO {nonce}: escaped "abc\\"def" tail',
    ]

    while len(clean_lines) < 140:
        candidate = nonce + " " + "".join(rng.choice(random_chars) for _ in range(rng.randrange(0, 100)))
        if parser_safe(candidate) and candidate not in clean_lines:
            clean_lines.append(candidate)

    evil_lines = []
    body_chars = string.ascii_letters + string.digits + " _-:./=[]{}(),!@#$%^&*"
    for index in range(140):
        prefix = "".join(rng.choice(ordinary) for _ in range(rng.randrange(1, 45)))
        body = "".join(rng.choice(body_chars) for _ in range(rng.randrange(0, 70)))
        candidate = f"{prefix} {nonce}-{index} \"{body}\\"
        assert not parser_safe(candidate)
        evil_lines.append(candidate)

    assert all(parser_safe(line) for line in clean_lines)
    assert all(not parser_safe(line) for line in evil_lines)

    with tempfile.TemporaryDirectory(prefix=f"hidden-{nonce}-") as td:
        clean_path = os.path.join(td, secrets.token_hex(8) + ".raw")
        evil_path = os.path.join(td, secrets.token_hex(8) + ".raw")
        mixed_path = os.path.join(td, secrets.token_hex(8) + ".raw")

        clean_data = b"".join(line.encode("ascii") + b"\n" for line in clean_lines)
        evil_data = b"".join(line.encode("ascii") + b"\n" for line in evil_lines)

        mixed_lines = [(line, True) for line in clean_lines] + [(line, False) for line in evil_lines]
        rng.shuffle(mixed_lines)
        mixed_data = b"".join(line.encode("ascii") + b"\n" for line, _ in mixed_lines)
        mixed_expected = b"".join(
            line.encode("ascii") + b"\n" for line, safe in mixed_lines if safe
        )

        with open(clean_path, "wb") as f:
            f.write(clean_data)
        with open(evil_path, "wb") as f:
            f.write(evil_data)
        with open(mixed_path, "wb") as f:
            f.write(mixed_data)

        assert invoke_filter(filter_path, evil_path) == b"", "malformed lines were retained"
        assert invoke_filter(filter_path, clean_path) == clean_data, "clean lines were modified or dropped"
        assert invoke_filter(filter_path, mixed_path) == mixed_expected, "mixed corpus was filtered incorrectly"

        safe_no_newline = os.path.join(td, secrets.token_hex(8))
        unsafe_no_newline = os.path.join(td, secrets.token_hex(8))
        safe_tail = f'{nonce}: open "quote but no slash'.encode("ascii")
        unsafe_tail = f'{nonce}: open "quote ending in slash\\'.encode("ascii")
        with open(safe_no_newline, "wb") as f:
            f.write(safe_tail)
        with open(unsafe_no_newline, "wb") as f:
            f.write(unsafe_tail)
        assert invoke_filter(filter_path, safe_no_newline) == safe_tail
        assert invoke_filter(filter_path, unsafe_no_newline) == b""
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
