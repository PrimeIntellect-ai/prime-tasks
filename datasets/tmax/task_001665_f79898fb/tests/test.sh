#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess

HANDLER = "/app/upload_handler"
SCRIPT = "/home/user/detect.sh"


def sanitize_with_binary(path):
    proc = subprocess.run(
        [HANDLER, path],
        text=True,
        capture_output=True,
        timeout=2,
    )
    assert proc.returncode == 0, f"upload_handler failed for {path!r}: {proc.stderr}"
    assert proc.stdout.endswith("\n"), "upload_handler produced malformed output"
    return proc.stdout[:-1]


def escapes_parent(path):
    # Resolve the sanitized path lexically relative to an upload directory.
    if path.startswith("/"):
        return True

    depth = 0
    for component in path.split("/"):
        if component in ("", "."):
            continue
        if component == "..":
            if depth == 0:
                return True
            depth -= 1
        else:
            depth += 1
    return False


def oracle(path):
    return int(escapes_parent(sanitize_with_binary(path)))


def word():
    alphabet = string.ascii_lowercase + string.digits + "_-"
    return "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(10) + 1))


def random_path():
    mode = secrets.randbelow(9)

    if mode == 0:
        return "/".join(word() for _ in range(secrets.randbelow(6) + 1))
    if mode == 1:
        return "../" * (secrets.randbelow(8) + 1) + word()
    if mode == 2:
        pieces = []
        for _ in range(secrets.randbelow(8) + 1):
            pieces.append("." * (secrets.randbelow(9) + 1))
            pieces.append("/" * (secrets.randbelow(3) + 1))
        pieces.append(word())
        return "".join(pieces)
    if mode == 3:
        components = []
        choices = [".", "..", "...", "....", ".....", word()]
        for _ in range(secrets.randbelow(10) + 1):
            components.append(secrets.choice(choices))
        result = components[0]
        for component in components[1:]:
            result += "/" * (secrets.randbelow(3) + 1) + component
        return result
    if mode == 4:
        alphabet = "..../" + string.ascii_lowercase + string.digits + "_-"
        return "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(100) + 1))
    if mode == 5:
        # A terminal parent component is not removed by the binary.
        return secrets.choice(["", "./", ".//", "..././"]) + ".."
    if mode == 6:
        # Overlapping matches can create a new parent component.
        return "." * (secrets.randbelow(5) + 4) + "//" + word()
    if mode == 7:
        prefix = secrets.choice(["", "./", word() + "/", word() + "//"])
        return prefix + ("....//" * (secrets.randbelow(6) + 1)) + word()

    atoms = [word(), ".", "..", "...", "....", "../", "..//", "..././", "....//"]
    return "".join(secrets.choice(atoms) for _ in range(secrets.randbelow(12) + 1))


def test_detect_script_accuracy():
    assert os.path.isfile(HANDLER), f"Binary not found at {HANDLER}"
    assert os.access(HANDLER, os.X_OK), f"Binary at {HANDLER} is not executable"
    assert os.path.exists(SCRIPT), f"Script not found at {SCRIPT}"
    assert os.path.isfile(SCRIPT), f"Script at {SCRIPT} is not a regular file"
    assert os.access(SCRIPT, os.X_OK), f"Script at {SCRIPT} is not executable"

    # Retain the original examples, but derive their answers from the recovered
    # binary rather than trusting template labels.
    base_paths = [
        "test.txt",
        "images/pic.png",
        "../etc/passwd",
        "....//etc/passwd",
        "images/....//secret.txt",
        "..../....//",
        "..././",
    ]

    cases = []
    seen = set()
    positive = 0
    negative = 0

    for path in base_paths:
        label = oracle(path)
        cases.append((path, label))
        seen.add(path)
        positive += label
        negative += 1 - label

    # Create an unpredictable, balanced held-out corpus from a broad grammar.
    attempts = 0
    while len(cases) < 1000:
        attempts += 1
        assert attempts < 100000, "Unable to generate balanced test corpus"
        path = random_path()
        if not path or "\n" in path or path in seen:
            continue
        label = oracle(path)
        if label and positive >= 500:
            continue
        if not label and negative >= 500:
            continue
        seen.add(path)
        cases.append((path, label))
        positive += label
        negative += 1 - label

    # Secretly permute the corpus so output cannot rely on category ordering.
    secrets.SystemRandom().shuffle(cases)
    test_input = "\n".join(path for path, _ in cases)
    expected = [label for _, label in cases]

    try:
        process = subprocess.run(
            ["/bin/bash", SCRIPT],
            input=test_input,
            text=True,
            capture_output=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        assert False, "Script execution timed out after 15 seconds"

    assert process.returncode == 0, (
        f"Script exited with error code {process.returncode}\nStderr: {process.stderr}"
    )

    outputs = process.stdout.strip().split("\n")
    assert len(outputs) == len(expected), (
        f"Expected {len(expected)} lines of output, got {len(outputs)}"
    )

    correct = sum(
        str(output).strip() == str(expected_label)
        for output, expected_label in zip(outputs, expected)
    )
    accuracy = correct / len(expected)
    assert accuracy >= 0.95, f"Accuracy: {accuracy:.4f} is below the threshold of 0.95"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
