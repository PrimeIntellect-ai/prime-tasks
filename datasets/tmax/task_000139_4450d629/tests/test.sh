#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shlex
import stat
import subprocess
import tempfile
from pathlib import Path

VALIDATOR = "/home/user/validator"
SOURCE = "/home/user/validator.c"
PIPELINE = "/home/user/ci_pipeline.sh"
FW_SCRIPT = "/home/user/fw_config.sh"


def diagram_values():
    result = subprocess.run(
        ["tesseract", "/app/diagram.png", "stdout", "--psm", "6"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    ns_match = re.search(r"ALLOWED[_ ]NAMESPACE\s*:\s*([A-Za-z0-9_.-]+)", result.stdout, re.I)
    port_match = re.search(r"FW[_ ]PORT\s*:\s*([0-9]+)", result.stdout, re.I)
    assert ns_match, f"Could not extract namespace from diagram OCR: {result.stdout!r}"
    assert port_match, f"Could not extract firewall port from diagram OCR: {result.stdout!r}"
    return ns_match.group(1), port_match.group(1)


def assert_executable_script(path):
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.stat(path).st_mode & 0o111, f"{path} is not executable."


def test_validator_exists_and_permissions():
    assert os.path.isfile(VALIDATOR), f"{VALIDATOR} does not exist."
    with open(VALIDATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "validator is not an ELF executable."

    permissions = stat.S_IMODE(os.stat(VALIDATOR).st_mode)
    assert permissions == 0o711, f"Expected permissions 711 (octal), but got {oct(permissions)}."


def test_source_and_pipeline_execution():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert_executable_script(PIPELINE)

    syntax = subprocess.run(["bash", "-n", PIPELINE], capture_output=True, text=True)
    assert syntax.returncode == 0, f"ci_pipeline.sh has invalid syntax: {syntax.stderr}"

    result = subprocess.run(["bash", PIPELINE], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"ci_pipeline.sh failed with status {result.returncode}:\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    assert os.path.isfile(VALIDATOR), "Pipeline did not produce /home/user/validator."
    assert stat.S_IMODE(os.stat(VALIDATOR).st_mode) == 0o711, "Pipeline did not set validator mode to 711."
    with open(VALIDATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Pipeline output is not an ELF executable."

    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), "Pipeline did not create /home/user/pipeline.log."
    lines = Path(log_path).read_text(errors="replace").splitlines()
    clean_files = glob.glob("/app/corpora/clean/*.yaml")
    evil_files = glob.glob("/app/corpora/evil/*.yaml")
    for path, expected_status in [(p, "pass") for p in clean_files] + [(p, "fail") for p in evil_files]:
        matching = [line for line in lines if path in line]
        assert matching, f"pipeline.log does not list {path}."
        assert any(re.search(rf"\b{expected_status}\b", line, re.I) for line in matching), (
            f"pipeline.log does not mark {path} as {expected_status}."
        )


def test_fw_config_script():
    assert os.path.isfile(FW_SCRIPT), f"{FW_SCRIPT} does not exist."
    assert_executable_script(FW_SCRIPT)

    content = Path(FW_SCRIPT).read_text()

    # Preserve the original component assertions.
    assert "iptables" in content, "iptables command not found in fw_config.sh."
    assert "-t nat" in content, "'-t nat' not found in fw_config.sh."
    assert "PREROUTING" in content, "'PREROUTING' not found in fw_config.sh."
    assert "80" in content, "Source port 80 not found in fw_config.sh."
    assert "8080" in content, "Destination port 8080 not found in fw_config.sh."

    syntax = subprocess.run(["bash", "-n", FW_SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"fw_config.sh has invalid bash syntax: {syntax.stderr}"

    _, expected_port = diagram_values()
    logical_lines = re.sub(r"\\\n", " ", content).splitlines()
    commands = []
    for line in logical_lines:
        try:
            words = shlex.split(line, comments=True, posix=True)
        except ValueError as exc:
            raise AssertionError(f"Cannot parse fw_config.sh command: {exc}")
        if words and os.path.basename(words[0]) == "iptables":
            commands.append(words)

    def has_pair(argv, flags, value):
        return any(argv[i] in flags and i + 1 < len(argv) and argv[i + 1] == value
                   for i in range(len(argv)))

    valid_rule = False
    for argv in commands:
        table_ok = has_pair(argv, {"-t", "--table"}, "nat")
        chain_ok = has_pair(argv, {"-A", "--append"}, "PREROUTING")
        protocol_ok = has_pair(argv, {"-p", "--protocol"}, "tcp")
        dport_ok = has_pair(argv, {"--dport", "--destination-port"}, "80")
        target_ok = has_pair(argv, {"-j", "--jump"}, "REDIRECT")
        to_port_ok = has_pair(argv, {"--to-port", "--to-ports"}, expected_port)
        if table_ok and chain_ok and protocol_ok and dport_ok and target_ok and to_port_ok:
            valid_rule = True
            break
    assert valid_rule, (
        "fw_config.sh must contain an actual iptables nat PREROUTING TCP rule "
        f"redirecting destination port 80 to {expected_port}."
    )


def run_validator(binary, args):
    try:
        return subprocess.run([binary] + args, capture_output=True, timeout=5).returncode
    except subprocess.TimeoutExpired:
        raise AssertionError(f"Validator timed out for arguments: {args!r}")


def exercise_validator(binary):
    namespace, _ = diagram_values()
    with tempfile.TemporaryDirectory(prefix="manifest-validator-") as td:
        cases = {
            "safe-random.yaml": (f"apiVersion: v1\nkind: Pod\nmetadata:\n  name: generated\n  namespace: {namespace}\nspec:\n  containers: []\n", 0),
            "wrong-random.yaml": ("apiVersion: v1\nkind: Pod\nmetadata:\n  namespace: unrelated-random-namespace\n", 1),
            "priv-random.yaml": (f"namespace: {namespace}\nprivileged: true\n", 1),
            "network-random.yaml": (f"namespace: {namespace}\nhostNetwork: true\n", 1),
            "path-random.yaml": (f"namespace: {namespace}\nvolumes:\n- hostPath:\n    path: /tmp/data\n", 1),
            "comment-random.yaml": (f"namespace: {namespace}\n# privileged: true\n", 1),
        }
        paths = []
        for filename, (content, expected) in cases.items():
            path = os.path.join(td, filename)
            Path(path).write_text(content)
            paths.append(path)
            actual = run_validator(binary, [path])
            assert actual == expected, f"{binary} returned {actual} for {filename}; expected {expected}."

        assert run_validator(binary, []) == 1, "Validator must exit 1 when no manifest argument is supplied."
        assert run_validator(binary, [paths[0], paths[1]]) == 1, "Validator must exit 1 when given two arguments."
        assert run_validator(binary, [os.path.join(td, "missing.yaml")]) == 1, "Validator must exit 1 for an unreadable manifest."


def test_generated_manifests_and_compilable_source():
    exercise_validator(VALIDATOR)
    with tempfile.TemporaryDirectory(prefix="source-build-") as td:
        rebuilt = os.path.join(td, "validator-from-source")
        result = subprocess.run(["gcc", SOURCE, "-o", rebuilt], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"validator.c does not compile with gcc: {result.stderr}"
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Compiled validator.c did not produce an ELF executable."
        exercise_validator(rebuilt)


def test_adversarial_corpus_validator():
    clean_corpus_path = "/app/corpora/clean/"
    evil_corpus_path = "/app/corpora/evil/"

    assert os.path.isfile(VALIDATOR), f"Validator binary {VALIDATOR} is missing."

    clean_files = glob.glob(os.path.join(clean_corpus_path, "*.yaml")) + glob.glob(os.path.join(clean_corpus_path, "*.yml"))
    evil_files = glob.glob(os.path.join(evil_corpus_path, "*.yaml")) + glob.glob(os.path.join(evil_corpus_path, "*.yml"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_corpus_path}."
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_corpus_path}."

    failed_clean = []
    for fpath in clean_files:
        if run_validator(VALIDATOR, [fpath]) != 0:
            failed_clean.append(os.path.basename(fpath))

    failed_evil = []
    for fpath in evil_files:
        if run_validator(VALIDATOR, [fpath]) == 0:
            failed_evil.append(os.path.basename(fpath))

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")

    assert not error_msgs, " | ".join(error_msgs)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
