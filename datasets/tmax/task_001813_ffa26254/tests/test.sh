#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import string
import subprocess
import tempfile
from pathlib import Path

FILTER_RE = re.compile(rb"PROJ-[0-9]{3}-XYZ")


def get_filter_path():
    for ext in ["sh", "py", ""]:
        path = f"/home/user/doc_filter.{ext}" if ext else "/home/user/doc_filter"
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def run_filter(filter_path, path):
    try:
        return subprocess.run(
            [filter_path, path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"Filter timed out on {path}")


def test_filter_exists_and_executable():
    filter_path = get_filter_path()
    assert filter_path is not None, "Executable doc_filter script not found in /home/user/"


def test_adversarial_corpus():
    filter_path = get_filter_path()
    assert filter_path is not None, "Filter script missing, cannot test corpus."

    # Preserve the original corpus assertions.
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    clean_modified = []
    evil_bypassed = []
    for path in clean_files:
        if run_filter(filter_path, path).returncode != 0:
            clean_modified.append(os.path.basename(path))
    for path in evil_files:
        if run_filter(filter_path, path).returncode == 0:
            evil_bypassed.append(os.path.basename(path))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    assert not errors, " | ".join(errors)

    # Exercise fresh, unpredictable paths and content so corpus filenames cannot
    # be hardcoded. Labels are derived here from the pattern in the voice memo.
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + " .,:;_/@![]{}()\n\t"

    clean_fragments = [
        b"PROJ-12-XYZ", b"PROJ-1234-XYZ", b"PROJ-123-XY",
        b"PROJ-123-XYZX", b"proj-123-XYZ", b"PROJ-123-xyz",
        b"PROJ_123_XYZ", b"PROJ-12A-XYZ", b"PROJ-\n123-XYZ",
        b"PROJ-123 -XYZ", b"PROJ-123-ABC", b"PROJ-１２３-XYZ",
        b"PROJECT-123-XYZ", b"PROJ--123-XYZ", b"PROJ-+123-XYZ",
        b"ordinary documentation", b"XYZ PROJ 123",
    ]

    cases = []
    for i in range(360):
        prefix = ''.join(rng.choice(alphabet) for _ in range(rng.randrange(0, 90))).encode()
        suffix = ''.join(rng.choice(alphabet) for _ in range(rng.randrange(0, 90))).encode()
        if i % 2:
            digits = ''.join(rng.choice(string.digits) for _ in range(3)).encode()
            marker = b"PROJ-" + digits + b"-XYZ"
            if i % 10 == 1:
                payload = marker
            elif i % 10 == 3:
                payload = prefix + marker + suffix
            elif i % 10 == 5:
                payload = prefix + marker + b" and PROJ-000-XYZ" + suffix
            elif i % 10 == 7:
                payload = b"A" + marker + b"B"
            else:
                payload = prefix + b"\n" + marker + b"\n" + suffix
        else:
            payload = prefix + rng.choice(clean_fragments) + suffix
            # Random filler could theoretically create the pattern accidentally;
            # the expected answer is always derived from actual bytes below.
        expected = 1 if FILTER_RE.search(payload) else 0
        cases.append((payload, expected))

    failures = []
    with tempfile.TemporaryDirectory(prefix="hidden-doc-corpus-") as td:
        rng.shuffle(cases)
        for index, (payload, expected) in enumerate(cases):
            name = secrets.token_hex(12) + rng.choice([".txt", ".md", ".data", ""])
            path = os.path.join(td, name)
            with open(path, "wb") as f:
                f.write(payload)
            result = run_filter(filter_path, path)
            if result.returncode != expected:
                failures.append(
                    f"case {index}: expected exit {expected}, got {result.returncode}"
                )
                if len(failures) >= 10:
                    break

    assert not failures, "Fresh adversarial corpus failures: " + " | ".join(failures)


def test_compiled_docs():
    compiled_path = "/home/user/compiled_docs.md"
    assert os.path.isfile(compiled_path), f"Compiled docs file missing: {compiled_path}"

    with open(compiled_path, "r") as f:
        content = f.read().strip()

    # Preserve the original final-state assertion.
    assert content == "Draft 3 text", \
        f"Compiled docs content is incorrect. Expected 'Draft 3 text', got: {content}"

    # Independently derive the eligible clean draft contents rather than trusting
    # the submitted filter or a hardcoded expected corpus label.
    cutoff = __import__('time').time() - 7 * 24 * 60 * 60
    expected_parts = []
    for path in sorted(Path("/home/user/drafts").rglob("*.md")):
        if path.stat().st_mtime >= cutoff:
            data = path.read_bytes()
            if not FILTER_RE.search(data):
                expected_parts.append(data.decode(errors="replace").strip())
    assert content == "\n".join(expected_parts), \
        "compiled_docs.md was not derived from the recent clean Markdown drafts"
    assert os.path.getmtime(compiled_path) >= max(
        os.path.getmtime(p) for p in Path("/home/user/drafts").rglob("*.md")
    ), "compiled_docs.md predates its input drafts"


def _without_shell_comments(text):
    output = []
    for line in text.splitlines():
        quote = None
        escaped = False
        kept = []
        for ch in line:
            if escaped:
                kept.append(ch)
                escaped = False
                continue
            if ch == "\\" and quote != "'":
                kept.append(ch)
                escaped = True
                continue
            if quote:
                kept.append(ch)
                if ch == quote:
                    quote = None
                continue
            if ch in ("'", '"'):
                quote = ch
                kept.append(ch)
            elif ch == "#":
                break
            else:
                kept.append(ch)
        output.append("".join(kept))
    return "\n".join(output)


def _has_real_flock_invocation(code):
    shell_call = re.compile(
        r"(?m)(?:^\s*|[;&|]\s*|\b(?:then|do|if)\s+|-exec\s+)"
        r"(?:sudo\s+|command\s+)?(?:/usr/bin/|/bin/)?flock(?:\s|$)"
    )
    python_call = re.compile(
        r"(?:subprocess\.(?:run|Popen|call|check_call|check_output)|os\.system)"
        r"\s*\([^\n]{0,160}[\"'][^\"']*flock(?:[\"'\s]|$)"
    )
    return bool(shell_call.search(code) or python_call.search(code))


def test_flock_used():
    candidates = []
    for history in ["/root/.bash_history", "/home/user/.bash_history"]:
        if os.path.isfile(history):
            candidates.append(history)

    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for filename in files:
            if filename.endswith((".sh", ".py")):
                candidates.append(os.path.join(root, filename))

    valid = []
    for path in candidates:
        try:
            raw = Path(path).read_text(errors="ignore")
        except OSError:
            continue
        code = _without_shell_comments(raw)
        if not _has_real_flock_invocation(code):
            continue
        # The locking invocation must be part of the actual draft compilation
        # pipeline, not an unrelated no-op such as `flock --help`.
        if ("compiled_docs.md" in code and "/home/user/drafts" in code
                and "doc_filter" in code
                and (">>" in code or re.search(r"open\s*\([^\n]+[\"']a", code))):
            valid.append(path)

    assert valid, (
        "No executable compilation command/script was found that invokes flock "
        "while filtering drafts and appending to compiled_docs.md"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
