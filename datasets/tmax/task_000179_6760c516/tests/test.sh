#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import uuid

import pytest

FILTER_SCRIPT = "/home/user/qemu_filter.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def run_filter(path, *extra_args, cwd=None):
    return subprocess.run(
        ["python3", FILTER_SCRIPT, path, *extra_args],
        cwd=cwd,
        capture_output=True,
        timeout=8,
    )


def test_filter_script_exists():
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script not found at {FILTER_SCRIPT}"
    result = subprocess.run(
        ["python3", "-m", "py_compile", FILTER_SCRIPT],
        capture_output=True,
        timeout=8,
    )
    assert result.returncode == 0, "Filter script is not valid Python"


def test_adversarial_corpus():
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script not found at {FILTER_SCRIPT}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}"

    failed_clean = []
    failed_evil = []

    for cf in clean_files:
        result = run_filter(cf)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(cf))

    for ef in evil_files:
        result = run_filter(ef)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(ef))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted: {', '.join(failed_evil)}")

    if errors:
        pytest.fail(" | ".join(errors))


def make_qemu_script(violations):
    rng = secrets.SystemRandom()
    ident = "n" + secrets.token_hex(4)
    memory = rng.choice([768, 1024, 1536, 3072, 6144])
    display = rng.randrange(0, 40)

    if "vnc" in violations:
        vnc_host = f"{rng.randrange(1, 224)}.{rng.randrange(0, 256)}.{rng.randrange(0, 256)}.{rng.randrange(1, 255)}"
        if vnc_host == "127.0.0.1":
            vnc_host = "0.0.0.0"
    else:
        vnc_host = "127.0.0.1"

    bridge = "br0" if "bridge" not in violations else "br" + str(rng.randrange(1, 10000))
    args = [
        "qemu-system-x86_64",
        "-m", str(memory),
        "-vnc", f"{vnc_host}:{display}",
        "-netdev", f"bridge,br={bridge},id={ident}",
        "-device", f"virtio-net-pci,netdev={ident}",
    ]

    if "virtfs" in violations:
        args.extend(["-virtfs", f"local,path=/tmp/{secrets.token_hex(5)},mount_tag=t{secrets.token_hex(3)},security_model=none"])
    if "fsdev" in violations:
        args.extend(["-fsdev", f"local,id=f{secrets.token_hex(3)},path=/tmp/{secrets.token_hex(5)},security_model=none"])
    if "port25" in violations:
        forwarding = rng.choice([
            "hostfwd=tcp::25-:25",
            "hostfwd=tcp:127.0.0.1:25-:2525",
            "hostfwd=tcp:0.0.0.0:25-10.0.2.15:25",
        ])
        args.extend(["-netdev", f"user,id=u{secrets.token_hex(3)},{forwarding}"])

    if rng.choice([True, False]):
        body = " \\\n  ".join(args)
    else:
        body = " ".join(args)
    return "#!/bin/bash\n" + body + "\n"


def test_generated_content_not_fixed_paths():
    # Expected outcomes are derived from the selected policy violations. All files
    # use unrelated random names in the same newly-created directory.
    cases = [
        set(), set(), set(),
        {"vnc"},
        {"bridge"},
        {"virtfs"},
        {"fsdev"},
        {"port25"},
        {"vnc", "fsdev"},
        {"bridge", "port25"},
    ]
    choices = ["vnc", "bridge", "virtfs", "fsdev", "port25"]
    rng = secrets.SystemRandom()
    for _ in range(8):
        if rng.choice([True, False]):
            cases.append(set())
        else:
            cases.append(set(rng.sample(choices, rng.randrange(1, 4))))
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="qf_" + secrets.token_hex(5) + "_") as directory:
        generated = []
        for violations in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".sh")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(make_qemu_script(violations))
            generated.append((path, 1 if violations else 0))

        rng.shuffle(generated)
        for path, expected in generated:
            result = run_filter(path)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)} expected {expected}, got {result.returncode}"
                )

    assert not failures, "Generated policy cases failed: " + " | ".join(failures)


def test_argument_and_read_errors():
    no_args = subprocess.run(["python3", FILTER_SCRIPT], capture_output=True, timeout=8)
    assert no_args.returncode == 1, "No-argument invocation must exit 1"

    with tempfile.TemporaryDirectory(prefix="qf_cli_") as directory:
        valid_path = os.path.join(directory, uuid.uuid4().hex + ".sh")
        with open(valid_path, "w", encoding="utf-8") as handle:
            handle.write(make_qemu_script(set()))

        extra = run_filter(valid_path, valid_path)
        assert extra.returncode == 1, "Invocation with more than one argument must exit 1"

        missing = os.path.join(directory, uuid.uuid4().hex + ".sh")
        assert run_filter(missing).returncode == 1, "Missing file must exit 1"
        assert run_filter(directory).returncode == 1, "Unreadable/non-file input must exit 1"

        relative = run_filter(os.path.basename(valid_path), cwd=directory)
        assert relative.returncode == 1, "Relative input path must be rejected"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
