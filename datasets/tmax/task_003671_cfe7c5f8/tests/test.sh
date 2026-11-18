#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
import tempfile


def run_scanner(scanner_path, filepath):
    return subprocess.run(
        ["python3", scanner_path, filepath],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_scanner_clean_corpus():
    scanner_path = "/home/user/scanner.py"
    assert os.path.isfile(scanner_path), f"{scanner_path} is missing"

    clean_dir = "/app/corpora/clean"
    assert os.path.isdir(clean_dir), f"{clean_dir} is missing"

    files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(files) > 0, f"No files found in {clean_dir}"

    failed_files = []
    for filename in files:
        filepath = os.path.join(clean_dir, filename)
        result = run_scanner(scanner_path, filepath)
        if result.returncode != 0 or "CLEAN" not in result.stdout:
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(files)} clean files modified/rejected: {', '.join(failed_files)}"


def test_scanner_evil_corpus():
    scanner_path = "/home/user/scanner.py"
    assert os.path.isfile(scanner_path), f"{scanner_path} is missing"

    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(evil_dir), f"{evil_dir} is missing"

    files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(files) > 0, f"No files found in {evil_dir}"

    failed_files = []
    for filename in files:
        filepath = os.path.join(evil_dir, filename)
        result = run_scanner(scanner_path, filepath)
        if result.returncode != 1 or "EVIL" not in result.stdout:
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(files)} evil files bypassed: {', '.join(failed_files)}"


def test_scanner_executable_and_generated_cases():
    scanner_path = "/home/user/scanner.py"
    assert os.path.isfile(scanner_path), f"{scanner_path} is missing"
    mode = os.stat(scanner_path).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "scanner.py is not executable"

    rng = random.SystemRandom()
    cases = [
        ([0.0], "CLEAN", 0),
        ([0.0, 42.499], "CLEAN", 0),
        ([0.0, 42.5], "EVIL", 1),
        ([100.0, 57.5], "EVIL", 1),
        ([3.0, -10.0, 5.0, -1.0], "CLEAN", 0),
    ]

    # Create unpredictable paths and varied sequences whose expected results are
    # independently derived from the specified instability metric.
    for _ in range(30):
        count = rng.randint(2, 12)
        values = [rng.uniform(-1000.0, 1000.0)]
        for _ in range(count - 1):
            values.append(values[-1] + rng.uniform(-30.0, 30.0))
        metric = sum(abs(b - a) for a, b in zip(values, values[1:]))
        expected = "CLEAN" if metric < 42.5 else "EVIL"
        cases.append((values, expected, 0 if expected == "CLEAN" else 1))

    with tempfile.TemporaryDirectory(prefix="artifact_cases_") as case_dir:
        rng.shuffle(cases)
        for index, (values, expected, expected_code) in enumerate(cases):
            path = os.path.join(case_dir, f"sample_{rng.randrange(10**12):012d}_{index}.dat")
            with open(path, "w") as f:
                for value in values:
                    f.write(repr(value) + "\n")

            result = run_scanner(scanner_path, path)
            assert result.returncode == expected_code, (
                f"Wrong exit code for metric {sum(abs(b-a) for a,b in zip(values, values[1:]))}: "
                f"expected {expected_code}, got {result.returncode}; stderr={result.stderr!r}"
            )
            assert result.stdout.strip() == expected, (
                f"Wrong output for generated artifact: expected {expected!r}, got {result.stdout!r}"
            )


def strip_comments(content):
    return re.sub(r'#.*$', '', content, flags=re.MULTILINE)


def matching_block(content, open_brace):
    depth = 0
    for pos in range(open_brace, len(content)):
        if content[pos] == '{':
            depth += 1
        elif content[pos] == '}':
            depth -= 1
            if depth == 0:
                return content[open_brace + 1:pos]
    raise AssertionError("Unbalanced braces in Nginx configuration")


def find_blocks(content, header_pattern):
    found = []
    for match in re.finditer(header_pattern + r'\s*\{', content):
        brace = content.find('{', match.start())
        found.append(matching_block(content, brace))
    return found


def test_nginx_config_validity_and_content():
    nginx_conf = "/home/user/nginx.conf"
    assert os.path.isfile(nginx_conf), f"{nginx_conf} is missing"

    with open(nginx_conf, 'r') as f:
        content = f.read()

    # Preserve the original content assertions.
    assert re.search(r'listen\s+8080\b', content), "Nginx config does not listen on port 8080"
    assert re.search(r'proxy_pass\s+http://127\.0\.0\.1:9000\b', content), "Nginx config does not proxy to http://127.0.0.1:9000"
    assert re.search(r'limit_req_zone\s+.*zone=upload_limit:10m\s+rate=10r/s\b', content), "Nginx config does not define the correct limit_req_zone"

    # Validate the actual configuration with Nginx.
    prefix = "/tmp/nginx-verifier-prefix"
    os.makedirs(os.path.join(prefix, "logs"), exist_ok=True)
    checked = subprocess.run(
        ["nginx", "-t", "-p", prefix + "/", "-c", nginx_conf],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert checked.returncode == 0, f"nginx -t failed:\n{checked.stdout}\n{checked.stderr}"

    # Ignore comments so fabricated text cannot satisfy the semantic checks.
    active = strip_comments(content)
    assert re.search(
        r'\blimit_req_zone\s+[^;]*\bzone=upload_limit:10m\s+rate=10r/s\s*;',
        active,
    ), "Active upload_limit zone must be 10m with a rate of exactly 10r/s"

    matching_servers = []
    for server in find_blocks(active, r'\bserver'):
        if re.search(r'\blisten\s+8080\b[^;]*;', server):
            matching_servers.append(server)
    assert matching_servers, "No active server block listens on port 8080"

    valid_route = False
    for server in matching_servers:
        server_limited = bool(re.search(r'\blimit_req\s+[^;]*\bzone=upload_limit\b[^;]*;', server))
        for location in find_blocks(server, r'\blocation\s+(?:\^~\s+)?/'):
            proxied = bool(re.search(r'\bproxy_pass\s+http://127\.0\.0\.1:9000\s*;', location))
            limited = server_limited or bool(
                re.search(r'\blimit_req\s+[^;]*\bzone=upload_limit\b[^;]*;', location)
            )
            if proxied and limited:
                valid_route = True
                break
    assert valid_route, (
        "The port 8080 server must proxy location / to 127.0.0.1:9000 and apply "
        "limit_req using upload_limit"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
