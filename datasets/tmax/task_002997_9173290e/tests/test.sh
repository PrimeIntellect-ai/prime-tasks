#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tempfile

SETUP_SCRIPT = "/home/user/setup_env.sh"
CLASSIFY_SCRIPT = "/home/user/classify_routes.sh"
MONITOR_STATE = "/home/user/monitor_state"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
RNG = secrets.SystemRandom()


def run_classifier(path, *extra):
    return subprocess.run(
        ["bash", CLASSIFY_SCRIPT, path, *extra],
        capture_output=True,
        text=True,
        timeout=5,
    )


def valid_ip():
    while True:
        third = RNG.randrange(256)
        fourth = RNG.randrange(256)
        if (third, fourth) not in ((0, 0), (255, 255)):
            return f"10.42.{third}.{fourth}"


def outside_ip():
    while True:
        first = RNG.randrange(1, 224)
        second = RNG.randrange(256)
        if (first, second) != (10, 42):
            return f"{first}.{second}.{RNG.randrange(256)}.{RNG.randrange(1, 255)}"


def valid_line():
    return f"ROUTE ADD {valid_ip()} GW {valid_ip()}"


def clean_document():
    return "\n".join(valid_line() for _ in range(RNG.randrange(1, 9))) + "\n"


def evil_document(kind):
    lines = [valid_line() for _ in range(RNG.randrange(1, 6))]
    target = valid_ip()
    gateway = valid_ip()

    if kind == "oob_target":
        bad = f"ROUTE ADD {outside_ip()} GW {gateway}"
    elif kind == "oob_gateway":
        bad = f"ROUTE ADD {target} GW {outside_ip()}"
    elif kind == "network_address":
        bad = f"ROUTE ADD 10.42.0.0 GW {gateway}"
    elif kind == "broadcast_address":
        bad = f"ROUTE ADD {target} GW 10.42.255.255"
    elif kind == "bad_octet":
        bad = f"ROUTE ADD 10.42.{RNG.randrange(256)}.{RNG.randrange(256, 1000)} GW {gateway}"
    elif kind == "short_ip":
        bad = f"ROUTE ADD 10.42.{RNG.randrange(256)} GW {gateway}"
    elif kind == "long_ip":
        bad = f"ROUTE ADD {target}.{RNG.randrange(10)} GW {gateway}"
    elif kind == "wrong_verb":
        bad = f"ROUTE DELETE {target} GW {gateway}"
    elif kind == "missing_gateway_keyword":
        bad = f"ROUTE ADD {target} {gateway}"
    elif kind == "extra_field":
        bad = f"ROUTE ADD {target} GW {gateway} INJECTED"
    elif kind == "garbage":
        bad = f"INVALID ROUTE {secrets.token_hex(8)}"
    elif kind == "blank_line":
        bad = ""
    else:
        raise AssertionError(kind)

    lines.insert(RNG.randrange(len(lines) + 1), bad)
    return "\n".join(lines) + "\n"


def test_setup_env_idempotent_and_correct():
    assert os.path.isfile(SETUP_SCRIPT), f"Setup script missing: {SETUP_SCRIPT}"

    res1 = subprocess.run(["bash", SETUP_SCRIPT], capture_output=True, text=True)
    assert res1.returncode == 0, f"setup_env.sh failed on first run. stderr: {res1.stderr}"

    for d in ["active", "archive", "quarantine"]:
        d_path = os.path.join(MONITOR_STATE, d)
        assert os.path.isdir(d_path), f"Directory {d_path} missing"
        mode = stat.S_IMODE(os.stat(d_path).st_mode)
        assert mode == 0o700, f"Directory {d_path} has incorrect permissions: {oct(mode)}, expected 0o700"

    link_path = os.path.join(MONITOR_STATE, "latest")
    assert os.path.islink(link_path), f"Symlink {link_path} missing"
    target = os.readlink(link_path)
    expected_targets = ["active", os.path.join(MONITOR_STATE, "active"), f"{MONITOR_STATE}/active"]
    assert target in expected_targets, f"Symlink target incorrect: {target}"

    res2 = subprocess.run(["bash", SETUP_SCRIPT], capture_output=True, text=True)
    assert res2.returncode == 0, f"setup_env.sh failed on second run (not idempotent). stderr: {res2.stderr}"

    assert os.path.islink(link_path), f"Symlink {link_path} missing after second run"
    target2 = os.readlink(link_path)
    assert target2 in expected_targets, f"Symlink target incorrect after second run: {target2}"


def test_classify_routes_original_corpus():
    assert os.path.isfile(CLASSIFY_SCRIPT), f"Classify script missing: {CLASSIFY_SCRIPT}"

    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]

    assert len(clean_files) > 0, "Clean corpus is empty or missing"
    assert len(evil_files) > 0, "Evil corpus is empty or missing"

    clean_failed = []
    for cf in clean_files:
        if run_classifier(cf).returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        if run_classifier(ef).returncode == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    assert not errors, " | ".join(errors)


def test_classify_routes_runtime_generated_adversarial_cases():
    assert os.path.isfile(CLASSIFY_SCRIPT), f"Classify script missing: {CLASSIFY_SCRIPT}"

    kinds = [
        "oob_target", "oob_gateway", "network_address", "broadcast_address",
        "bad_octet", "short_ip", "long_ip", "wrong_verb",
        "missing_gateway_keyword", "extra_field", "garbage", "blank_line",
    ]
    cases = []
    for _ in range(48):
        cases.append((True, clean_document()))
    for kind in kinds:
        for _ in range(6):
            cases.append((False, evil_document(kind)))
    RNG.shuffle(cases)

    # Every generated document is tested through the exact same unpredictable path,
    # so path- and filename-based classifiers cannot distinguish clean from evil.
    with tempfile.TemporaryDirectory(prefix=f"route-check-{secrets.token_hex(8)}-") as td:
        path = os.path.join(td, f"routes-{secrets.token_hex(8)}.log")
        for index, (should_accept, contents) in enumerate(cases):
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(contents)
            result = run_classifier(path)
            if should_accept:
                assert result.returncode == 0, f"runtime-generated clean case {index} was rejected: {result.stderr}"
            else:
                assert result.returncode != 0, f"runtime-generated evil case {index} was accepted: {contents!r}"


def test_classify_routes_requires_exactly_one_argument():
    no_arg = subprocess.run(["bash", CLASSIFY_SCRIPT], capture_output=True, text=True, timeout=5)
    assert no_arg.returncode != 0, "classifier accepted zero arguments"

    with tempfile.TemporaryDirectory() as td:
        first = os.path.join(td, "first.log")
        second = os.path.join(td, "second.log")
        for path in (first, second):
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(clean_document())
        two_args = run_classifier(first, second)
        assert two_args.returncode != 0, "classifier accepted two arguments"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
