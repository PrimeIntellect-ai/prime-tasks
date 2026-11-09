#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/log_filter"
SOURCE = "/home/user/log_filter.cpp"
PARSER = "/app/vendored/jsonparse-1.2/src/parser.cpp"
INCLUDE = "/app/vendored/jsonparse-1.2/include"


def run_filter(data):
    result = subprocess.run(
        [EXECUTABLE], input=data, capture_output=True, timeout=5
    )
    assert result.returncode == 0, (
        f"log_filter exited with {result.returncode}; stderr={result.stderr!r}"
    )
    return result.stdout


def nonempty_stripped_lines(data):
    return [line.strip() for line in data.decode("utf-8", errors="replace").splitlines() if line.strip()]


def strip_cpp_comments(text):
    text = re.sub(r"/\\*.*?\\*/", "", text, flags=re.S)
    return re.sub(r"//[^\\n]*", "", text)


def test_log_filter_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE), f"Source {SOURCE} does not exist."


def test_clean_corpus_accepted():
    clean_files = glob.glob("/home/user/logs/clean/*.jsonl")
    assert clean_files, "No clean log files found."
    failed = []
    for path in clean_files:
        with open(path, "rb") as f:
            input_data = f.read()
        if nonempty_stripped_lines(run_filter(input_data)) != nonempty_stripped_lines(input_data):
            failed.append(os.path.basename(path))
    assert not failed, f"Clean files modified or rejected: {', '.join(failed)}"


def test_evil_corpus_rejected():
    evil_files = glob.glob("/home/user/logs/evil/*.jsonl")
    assert evil_files, "No evil log files found."
    failed = []
    for path in evil_files:
        with open(path, "rb") as f:
            input_data = f.read()
        if nonempty_stripped_lines(run_filter(input_data)):
            failed.append(os.path.basename(path))
    assert not failed, f"Evil files bypassed: {', '.join(failed)}"


def test_vendored_library_bug_fixed_and_compiles():
    assert os.path.isfile(PARSER), f"{PARSER} does not exist."
    with open(PARSER, encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions, but apply them to code with comments removed
    # so a comment cannot masquerade as the repair.
    code = strip_cpp_comments(content)
    compact = re.sub(r"\\s+", "", code)
    assert "j<3" not in compact, "The deliberate j<3 bug remains in executable code"
    assert any(token in compact for token in ("j<4", "j<=3", "j!=4")), (
        "The Unicode loop was not fixed to process four digits"
    )
    assert re.search(
        r"for\\s*\\([^;]*;\\s*j\\s*(?:<\\s*4|<=\\s*3|!=\\s*4)", code
    ), "The four-digit condition must be part of an actual for loop"

    probe = r'''#include "jsonparse.h"
#include <string>
int main() {
    std::string s = R"({"timestamp":"t","source_ip":"1.2.3.4","event_type":"x\u2028y","bytes_transferred":1})";
    jsonparse::JsonObject o = jsonparse::parse(s);
    if (!o.valid) return 1;
    if (o.fields.count("event_type") != 1) return 2;
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        probe_cpp = os.path.join(td, "probe.cpp")
        probe_bin = os.path.join(td, "probe")
        with open(probe_cpp, "w", encoding="utf-8") as f:
            f.write(probe)
        build = subprocess.run(
            ["g++", "-std=c++17", "-I" + INCLUDE, probe_cpp, PARSER, "-o", probe_bin],
            capture_output=True, text=True, timeout=20
        )
        assert build.returncode == 0, f"Vendored parser does not compile: {build.stderr}"
        result = subprocess.run([probe_bin], capture_output=True, timeout=5)
        assert result.returncode == 0, "Vendored parser failed on a four-digit Unicode escape"


def test_filter_source_uses_vendored_parser():
    with open(SOURCE, encoding="utf-8", errors="replace") as f:
        code = strip_cpp_comments(f.read())
    assert re.search(r"#\\s*include\\s*[<\"]jsonparse\\.h[>\"]", code), (
        "log_filter.cpp does not include the vendored parser API"
    )
    assert re.search(r"\\bjsonparse\\s*::\\s*parse\\s*\\(", code), (
        "log_filter.cpp does not call jsonparse::parse"
    )


def make_dynamic_cases():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    valid = []
    invalid = []

    edge_ips = ["0.0.0.0", "255.255.255.255", "1.2.3.4", "127.0.0.1"]
    for i in range(36):
        ip = edge_ips[i] if i < len(edge_ips) else ".".join(str(rng.randrange(256)) for _ in range(4))
        amount = rng.randrange(0, 10**9)
        obj = {
            "timestamp": f"2099-07-{(i % 28) + 1:02d}T12:{i % 60:02d}:00Z-{secrets.token_hex(4)}",
            "source_ip": ip,
            "event_type": "event-" + secrets.token_hex(5) + ("-☃-quoted-\\\"-slash-\\\\" if i % 5 == 0 else ""),
            "bytes_transferred": str(amount) if i % 2 else amount,
        }
        if i % 3 == 0:
            # Nested and similarly named decoys ensure fields are read at object level,
            # rather than found by substring matching.
            obj = {
                "metadata": {"source_ip": "999.999.999.999", "bytes_transferred": -1},
                "source_ip_backup": "300.1.1.1",
                **obj,
                "extra": [True, None, {"bytes_transferred": -9}],
            }
        if i % 4 == 0:
            order = ["event_type", "bytes_transferred", "timestamp", "source_ip"]
            obj = {k: obj[k] for k in order} | {k: v for k, v in obj.items() if k not in order}
        separators = (",", ":") if i % 2 else (", ", ": ")
        valid.append(json.dumps(obj, ensure_ascii=True, separators=separators))

    bad_ips = [
        "256.1.2.3", "1.2.3.256", "-1.2.3.4", "1.2.3", "1.2.3.4.5",
        "1..2.3", "1.2.3.a", " 1.2.3.4", "1.2.3.4 ", "01.2.3.4"
    ]
    for i in range(30):
        base = {
            "timestamp": "dynamic-" + secrets.token_hex(5),
            "source_ip": ".".join(str(rng.randrange(256)) for _ in range(4)),
            "event_type": "evt-" + secrets.token_hex(4),
            "bytes_transferred": rng.randrange(10000),
        }
        mode = i % 5
        if mode == 0:
            base["source_ip"] = rng.choice(bad_ips)
        elif mode == 1:
            n = rng.randrange(1, 100000)
            base["bytes_transferred"] = -n if i % 2 else str(-n)
        elif mode == 2:
            del base[rng.choice(list(base.keys()))]
        elif mode == 3:
            base["bytes_transferred"] = rng.choice([None, True, "12x", "3.14", {}, []])
        else:
            # All required-looking values exist only below the top-level object.
            base = {"wrapper": base, "note": "not a log record"}
        invalid.append(json.dumps(base, ensure_ascii=True))

    token = secrets.token_hex(6)
    invalid.extend([
        '{"timestamp":"' + token + '","source_ip":"1.2.3.4","event_type":"x","bytes_transferred":01}',
        '{"timestamp":"' + token + '","source_ip":"1.2.3.4","event_type":"x","bytes_transferred":1} trailing',
        '{"timestamp":"' + token + '","source_ip":"1.2.3.4","event_type":"x","bytes_transferred":1',
        '{timestamp:"' + token + '","source_ip":"1.2.3.4","event_type":"x","bytes_transferred":1}',
        '{"timestamp":"' + token + '","source_ip":"1.2.3.4","event_type":"bad\\q","bytes_transferred":1}',
        '[{"timestamp":"' + token + '","source_ip":"1.2.3.4","event_type":"x","bytes_transferred":1}]',
        'null',
        'not-json-' + token,
    ])
    return valid, invalid


def test_dynamic_json_lines_and_constraints():
    valid, invalid = make_dynamic_cases()

    # Exercise independently so accepting or rejecting one line cannot hide errors
    # on another line.
    for line in valid:
        data = (line + "\n").encode("utf-8")
        assert run_filter(data) == data, f"Valid dynamic record was changed or rejected: {line}"
    for line in invalid:
        data = (line + "\n").encode("utf-8")
        assert run_filter(data) == b"", f"Invalid dynamic record was accepted: {line}"

    # Also verify true per-line behavior on a mixed stream in unpredictable order.
    tagged = [(line, True) for line in valid] + [(line, False) for line in invalid]
    random.SystemRandom().shuffle(tagged)
    input_data = ("\n".join(line for line, _ in tagged) + "\n").encode("utf-8")
    expected = ("".join(line + "\n" for line, good in tagged if good)).encode("utf-8")
    assert run_filter(input_data) == expected
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
