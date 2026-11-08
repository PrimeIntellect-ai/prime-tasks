#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import resource
import shlex
import subprocess
import tempfile
import uuid

import pytest

LINTER_PATH = "/home/user/config_linter.py"
ROUTER_PATH = "/app/alert-router"
EVIL_CORPUS = "/var/opt/verifier/corpus/evil/"
CLEAN_CORPUS = "/var/opt/verifier/corpus/clean/"


def run_linter(args, timeout=5):
    return subprocess.run(
        [LINTER_PATH] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def disable_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def make_hidden_cases(root):
    rng = random.SystemRandom()
    token = uuid.uuid4().hex
    cases = []

    def add(data):
        path = os.path.join(root, uuid.uuid4().hex + ".cfg")
        with open(path, "wb") as f:
            f.write(data)
        cases.append(path)

    # Directed boundary and validation cases.
    add(b"[MailingList]\nHealthCheckURL=https://" + token.encode() + b".example/health\n")
    add(b"HealthCheckURL=https://example.com/health\n")
    add(b"[MailingList]\n")
    add(b"[MailingList]\nHealthCheckURL=http://example.com/health\n")
    add(b"[MailingList]\nHealthCheckURL=https://localhost/health\n")
    add(b" [MailingList]\nHealthCheckURL=https://example.com/health\n")
    add(b"[MailingList] trailing text\nHealthCheckURL=https://example.com/health\n")
    add(b"[MailingList]\nHealthCheckURL=https://example.com/health\n" + b"X" * 63 + b"\n")
    add(b"[MailingList]\nHealthCheckURL=https://example.com/health\n" + b"X" * 62 + b"\n")
    add(b"[MailingList]\nHealthCheckURL=https://example.com/health\n" + b"X" * 64 + b"\n")
    add(b"[MailingList]\nHealthCheckURL=https://example.com/health\n" + b"X" * 64)
    add(b"[MailingList]\r\nHealthCheckURL=https://example.com/health\r\n")
    add(b"[MailingList]\nHealthCheckURL=https://example.com/health\nHealthCheckURL=http://bad.example/\n")
    add(b"HealthCheckURL=https://example.com/health\nnoise\n[MailingList]\n")

    url_lines = [
        b"HealthCheckURL=https://example.com/health\n",
        b"HealthCheckURL=https://" + token.encode() + b".invalid/status\n",
        b"HealthCheckURL=http://example.com/health\n",
        b"HealthCheckURL=ftp://example.com/health\n",
        b"HealthCheckURL=https://localhost/status\n",
        b"HealthCheckURL=https://api.example/localhost/check\n",
        b"healthcheckurl=https://example.com/health\n",
        b" HealthCheckURL=https://example.com/health\n",
    ]
    section_lines = [
        b"[MailingList]\n",
        b"[MailingList] " + token.encode() + b"\n",
        b" [MailingList]\n",
        b"[mailinglist]\n",
        b"[OtherSection]\n",
    ]

    # Runtime-randomized cases prevent path/content lookup solutions. Expected
    # results are obtained from the actual daemon before it is hidden.
    for _ in range(110):
        lines = []
        if rng.randrange(5) != 0:
            lines.append(rng.choice(section_lines))
        for _ in range(rng.randrange(4)):
            lines.append(rng.choice(url_lines))
        for _ in range(rng.randrange(5)):
            length = rng.choice([0, 1, 7, 31, 62, 63, 64, 65, 200, 1023, 1024])
            ch = bytes([rng.randrange(ord('A'), ord('Z') + 1)])
            lines.append(ch * length + b"\n")
        rng.shuffle(lines)
        data = b"".join(lines)
        if data and rng.randrange(4) == 0 and data.endswith(b"\n"):
            data = data[:-1]
        add(data)

    return cases


@pytest.fixture(scope="session", autouse=True)
def hidden_oracle_and_offline_guard():
    assert os.path.isfile(ROUTER_PATH), "Reference daemon is missing"
    temp_root = tempfile.mkdtemp(prefix="router-hidden-")
    os.chmod(temp_root, 0o700)
    case_root = tempfile.mkdtemp(prefix="router-cases-")
    marker = os.path.join(temp_root, "invoked")
    saved_router = os.path.join(temp_root, "reference-daemon")

    cases = make_hidden_cases(case_root)
    expected = {}
    for path in cases:
        result = subprocess.run(
            [ROUTER_PATH, path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            preexec_fn=disable_core_dumps,
        )
        expected[path] = (result.returncode == 0)

    assert sum(expected.values()) >= 10, "Generated corpus lacks clean cases"
    assert sum(not value for value in expected.values()) >= 10, "Generated corpus lacks rejected cases"

    # Remove the proprietary daemon while every linter invocation occurs. A
    # sentinel at its former path records any attempted daemon execution.
    os.rename(ROUTER_PATH, saved_router)
    with open(ROUTER_PATH, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nprintf invoked >> " + shlex.quote(marker) + "\nexit 97\n")
    os.chmod(ROUTER_PATH, 0o755)

    try:
        yield {"expected": expected, "marker": marker}
    finally:
        try:
            if os.path.lexists(ROUTER_PATH):
                os.unlink(ROUTER_PATH)
            os.rename(saved_router, ROUTER_PATH)
        finally:
            import shutil
            shutil.rmtree(case_root, ignore_errors=True)
            shutil.rmtree(temp_root, ignore_errors=True)


def test_linter_exists_and_executable():
    assert os.path.exists(LINTER_PATH), f"Linter script {LINTER_PATH} is missing."
    assert os.path.isfile(LINTER_PATH), f"{LINTER_PATH} is not a file."
    assert os.access(LINTER_PATH, os.X_OK), f"{LINTER_PATH} is not executable."
    with open(LINTER_PATH, "rb") as f:
        first_line = f.readline(256).lower()
    assert first_line.startswith(b"#!") and b"python" in first_line, \
        "The executable must be a Python script with a Python shebang."


def test_exactly_one_argument(hidden_oracle_and_offline_guard):
    expected = hidden_oracle_and_offline_guard["expected"]
    clean_path = next(path for path, accepted in expected.items() if accepted)
    assert run_linter([]).returncode != 0, "Linter accepted zero arguments"
    assert run_linter([clean_path, clean_path]).returncode != 0, \
        "Linter accepted more than one argument"


def test_linter_behavior_against_corpora():
    assert os.path.exists(EVIL_CORPUS), f"Evil corpus missing at {EVIL_CORPUS}"
    assert os.path.exists(CLEAN_CORPUS), f"Clean corpus missing at {CLEAN_CORPUS}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    for name in evil_files:
        if run_linter([os.path.join(EVIL_CORPUS, name)]).returncode == 0:
            evil_bypassed.append(name)

    clean_rejected = []
    for name in clean_files:
        if run_linter([os.path.join(CLEAN_CORPUS, name)]).returncode != 0:
            clean_rejected.append(name)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}")
    assert not errors, " | ".join(errors)


def test_randomized_behavior_matches_daemon(hidden_oracle_and_offline_guard):
    mismatches = []
    for path, should_accept in hidden_oracle_and_offline_guard["expected"].items():
        result = run_linter([path])
        accepted = result.returncode == 0
        if accepted != should_accept:
            mismatches.append((os.path.basename(path), should_accept, result.returncode))
    assert not mismatches, f"Linter disagreed with daemon on {len(mismatches)} hidden cases: {mismatches[:8]}"


def test_daemon_was_not_invoked(hidden_oracle_and_offline_guard):
    assert not os.path.exists(hidden_oracle_and_offline_guard["marker"]), \
        "The linter attempted to invoke /app/alert-router"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
