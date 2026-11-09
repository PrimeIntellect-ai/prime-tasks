#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import secrets
import subprocess

PARSER = "/home/user/api_parser.sh"
RUNNER = "/home/user/test_runner.sh"
LOG = "/home/user/test_results.log"
REFERENCE = "/home/user/api_parser.py"

EXPECTED_LINES = [
    '{"id": "99", "data": "Bash is fun"}',
    '{"id": "42", "data": "Only Payload"}',
    '{"id": "7", "data": ""}',
]


def run_parser(url, expected):
    result = subprocess.run([PARSER, url], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f"api_parser.sh failed for {url!r}: {result.stderr}"
    assert result.stdout.strip() == expected, (
        f"api_parser.sh output mismatch for {url!r}. "
        f"Expected {expected!r}, got {result.stdout.strip()!r}."
    )


def read_nonempty_log_lines():
    with open(LOG, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_api_parser_sh_exists_and_executable():
    path = PARSER
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert re.match(r"^#!.*(?:/|\s)bash(?:\s|$)", first_line), (
        f"{path} must be a Bash script with a Bash shebang."
    )

    if os.path.isfile(REFERENCE):
        with open(path, "rb") as submitted, open(REFERENCE, "rb") as reference:
            assert submitted.read() != reference.read(), (
                "api_parser.sh must be a Bash translation, not a byte-identical copy "
                "of api_parser.py."
            )


def test_test_runner_sh_exists():
    path = RUNNER
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_test_results_log_content():
    assert os.path.exists(LOG), f"File {LOG} does not exist. Did you run test_runner.sh?"
    lines = read_nonempty_log_lines()
    assert len(lines) == 3, f"Expected 3 lines in {LOG}, found {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_LINES)):
        assert actual == expected, (
            f"Line {i+1} mismatch. Expected {expected!r}, got {actual!r}."
        )


def test_api_parser_sh_functionality():
    # Preserve the original fixed direct invocation.
    test_url = "http://example.com/api?payload=SGVsbG8gV29ybGQ=&id=123"
    run_parser(test_url, '{"id": "123", "data": "Hello World"}')


def test_api_parser_sh_dynamic_functionality():
    # Generate values only at verification time so a fixed-output fake cannot pass.
    cases = []
    for index in range(6):
        while True:
            token = secrets.token_hex(10)
            decoded = f"dynamic-{index}-{token}"
            encoded = base64.b64encode(decoded.encode()).decode()
            if "+" not in encoded and "/" not in encoded:
                break
        ident = f"id-{secrets.token_hex(7)}"
        if index % 2:
            url = f"http://host-{index}.invalid/path?payload={encoded}&extra=x&id={ident}"
        else:
            url = f"https://host-{index}.invalid/other?id={ident}&payload={encoded}&extra=x"
        cases.append((url, f'{{"id": "{ident}", "data": "{decoded}"}}'))

    missing_id_text = f"only-payload-{secrets.token_hex(8)}"
    missing_id_payload = base64.b64encode(missing_id_text.encode()).decode()
    cases.extend([
        (
            f"http://missing.invalid/api?payload={missing_id_payload}",
            f'{{"id": "", "data": "{missing_id_text}"}}',
        ),
        (
            f"http://missing.invalid/api?id={secrets.token_hex(9)}",
            None,
        ),
        (
            "http://missing.invalid/api?unrelated=value",
            '{"id": "", "data": ""}',
        ),
    ])

    for url, expected in cases:
        if expected is None:
            ident = url.split("id=", 1)[1].split("&", 1)[0]
            expected = f'{{"id": "{ident}", "data": ""}}'
        run_parser(url, expected)


def test_runner_calls_parser_exactly_and_redirects_output():
    required_urls = [
        "http://example.com/api?id=99&payload=QmFzaCBpcyBmdW4=",
        "http://test.local/run?payload=T25seSBQYXlsb2Fk&id=42",
        "http://app.net/v1?id=7",
    ]
    backup = "/tmp/api_parser.sh.verifier-backup"
    trace = "/tmp/api_parser_runner_trace"
    count = "/tmp/api_parser_runner_count"

    for path in (backup, trace, count):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    os.replace(PARSER, backup)
    try:
        spy = f'''#!/bin/bash
count_file={count!r}
trace_file={trace!r}
n=0
if [ -f "$count_file" ]; then
    IFS= read -r n < "$count_file"
fi
n=$((n + 1))
printf '%s\\n' "$n" > "$count_file"
printf '%s\\0' "$#" "$@" >> "$trace_file"
printf 'SPY-OUTPUT-%s\\n' "$n"
'''
        with open(PARSER, "w") as f:
            f.write(spy)
        os.chmod(PARSER, 0o755)

        try:
            os.unlink(LOG)
        except FileNotFoundError:
            pass

        result = subprocess.run([RUNNER], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"test_runner.sh failed: {result.stderr}"
        assert result.stdout == "", (
            "test_runner.sh must redirect parser standard output to test_results.log."
        )
        assert os.path.exists(trace), "test_runner.sh did not call /home/user/api_parser.sh."

        with open(trace, "rb") as f:
            fields = f.read().split(b"\0")
        if fields and fields[-1] == b"":
            fields.pop()

        calls = []
        pos = 0
        while pos < len(fields):
            argc = int(fields[pos].decode())
            pos += 1
            args = [field.decode() for field in fields[pos:pos + argc]]
            pos += argc
            calls.append(args)

        assert pos == len(fields), "Malformed parser invocation trace."
        assert calls == [[url] for url in required_urls], (
            "test_runner.sh must call api_parser.sh exactly three times, in the "
            f"prescribed order and with exactly the prescribed URLs; observed {calls!r}."
        )

        assert os.path.exists(LOG), "test_runner.sh did not create test_results.log."
        with open(LOG, "r") as f:
            spy_lines = f.read().splitlines()
        assert spy_lines == ["SPY-OUTPUT-1", "SPY-OUTPUT-2", "SPY-OUTPUT-3"], (
            "test_runner.sh did not redirect the three parser outputs, in order, "
            "into test_results.log."
        )
    finally:
        try:
            os.unlink(PARSER)
        except FileNotFoundError:
            pass
        os.replace(backup, PARSER)

    # Execute the submitted runner with the real parser and retain the required log.
    result = subprocess.run([RUNNER], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"test_runner.sh failed with the real parser: {result.stderr}"
    assert read_nonempty_log_lines() == EXPECTED_LINES, (
        "Running test_runner.sh with api_parser.sh did not generate the required log."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
