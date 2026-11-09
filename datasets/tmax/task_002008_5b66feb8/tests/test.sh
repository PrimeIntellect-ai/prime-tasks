#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import os
import secrets
import subprocess
import tempfile

REPO = "/home/user/data_pipeline"
SOURCE = os.path.join(REPO, "parser.cpp")
PARSER = os.path.join(REPO, "parser")
LOGS = os.path.join(REPO, "logs.txt")
OUTPUT = os.path.join(REPO, "output.txt")
TRACE = "/home/user/trace.log"
SECRET = "/home/user/secret.txt"

CANONICAL_LOGS = """[INFO] user: alice, token: tk_abc12345, status: active
[INFO] user: bob, token: tk_def67890, status: active
[INFO] user: charlie, token: tk_ghi11223, status: inactive
"""
CANONICAL_TOKENS = ["tk_abc12345", "tk_def67890", "tk_ghi11223"]
CANONICAL_TRACE = ["Token length: 11", "Token length: 11", "Token length: 11"]


def nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run_parser(executable):
    result = subprocess.run(
        [executable], cwd=REPO, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}: {result.stderr}"
    )


def reset_generated(trace_prefix=""):
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    with open(TRACE, "w") as f:
        f.write(trace_prefix)


def assert_generated(expected_tokens, expected_trace):
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is missing. Did you run the compiled parser?"
    lines = nonempty_lines(OUTPUT)
    assert lines == expected_tokens, (
        f"Output in {OUTPUT} is incorrect. It should contain exactly the parsed "
        f"tokens without extra characters or commas. Expected {expected_tokens}, got {lines}."
    )

    assert os.path.isfile(TRACE), f"{TRACE} is missing. Did you modify parser.cpp to append to this file?"
    lines = nonempty_lines(TRACE)
    assert lines == expected_trace, (
        f"Trace log in {TRACE} is incorrect. Expected {expected_trace}, got {lines}."
    )


def main():
    # Preserve the original secret assertion.
    assert os.path.isfile(SECRET), f"{SECRET} is missing. Did you write the secret to the correct file?"
    with open(SECRET, "r") as f:
        content = f.read().strip()
    expected_secret = "sk_live_9a8b7c6d5e4f"
    assert content == expected_secret, (
        f"Secret in {SECRET} is incorrect. Expected '{expected_secret}', got '{content}'."
    )

    # Require both the modified source and the requested compiled executable.
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    assert os.path.isfile(PARSER), f"{PARSER} is missing. Did you compile parser.cpp?"
    assert os.access(PARSER, os.X_OK), f"{PARSER} is not executable."
    with open(PARSER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PARSER} is not a compiled executable."

    # Regenerate and check the exact original final-state outputs by running parser.
    with open(LOGS, "w") as f:
        f.write(CANONICAL_LOGS)
    reset_generated()
    run_parser(PARSER)
    assert_generated(CANONICAL_TOKENS, CANONICAL_TRACE)

    # Compile the submitted source independently so a correct stale binary alone
    # cannot hide an unfixed parser.cpp.
    fd, rebuilt = tempfile.mkstemp(prefix="rebuilt_parser_", dir="/tmp")
    os.close(fd)
    os.remove(rebuilt)
    try:
        result = subprocess.run(
            ["g++", SOURCE, "-o", rebuilt], cwd=REPO,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert result.returncode == 0, f"parser.cpp does not compile: {result.stderr}"

        # Use unpredictable tokens of varying lengths and derive all expectations.
        suffixes = [secrets.token_hex(2), secrets.token_hex(7), secrets.token_hex(13)]
        tokens = ["tk_" + suffix for suffix in suffixes]
        dynamic_logs = "".join(
            f"[INFO] user: user{i}, token: {token}, status: active\n"
            for i, token in enumerate(tokens)
        )
        expected_trace = [f"Token length: {len(token)}" for token in tokens]
        with open(LOGS, "w") as f:
            f.write(dynamic_logs)

        # Exercise the submitted executable on derived inputs and verify append mode.
        sentinel = "audit sentinel"
        reset_generated(sentinel + "\n")
        run_parser(PARSER)
        assert_generated(tokens, [sentinel] + expected_trace)

        # Exercise a fresh build of parser.cpp on the same derived inputs.
        reset_generated(sentinel + "\n")
        run_parser(rebuilt)
        assert_generated(tokens, [sentinel] + expected_trace)
    finally:
        if os.path.exists(rebuilt):
            os.remove(rebuilt)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
