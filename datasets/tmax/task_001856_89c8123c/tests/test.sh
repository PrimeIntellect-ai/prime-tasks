#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.machinery
import inspect
import json
import os
import secrets
import shutil
import subprocess
import textwrap

import pytest

EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
SANITIZER_SCRIPT = "/app/sanitizer.py"
PYTHON_BIN = "/opt/venv/bin/python"
PROJECT_DIR = "/app/tlv_parser"


def run_sanitizer(path, env=None):
    return subprocess.run(
        [PYTHON_BIN, SANITIZER_SCRIPT, path],
        capture_output=True,
        timeout=15,
        env=env,
    )


def test_sanitizer_exists():
    assert os.path.isfile(SANITIZER_SCRIPT), f"{SANITIZER_SCRIPT} does not exist."


def test_rust_extension_builds_imports_and_exposes_deserializer():
    env = os.environ.copy()
    env["PATH"] = "/root/.cargo/bin:/opt/venv/bin:" + env.get("PATH", "")
    built = subprocess.run(
        ["/opt/venv/bin/maturin", "develop"],
        cwd=PROJECT_DIR,
        env=env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert built.returncode == 0, (
        "tlv_parser failed to compile with maturin develop:\n"
        + built.stdout + "\n" + built.stderr
    )

    probe = textwrap.dedent(r'''
        import importlib.machinery
        import inspect
        import json
        import os
        import tempfile
        import tlv_parser

        origin = getattr(tlv_parser, "__file__", "") or ""
        suffix_ok = any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)
        callables = []
        invoked = []
        for name in dir(tlv_parser):
            if name.startswith("_"):
                continue
            obj = getattr(tlv_parser, name)
            if inspect.isclass(obj) or not callable(obj):
                continue
            callables.append(name)
            attempts = [
                (b"clean data 1\n",),
                (bytearray(b"clean data 1\n"),),
            ]
            fd, path = tempfile.mkstemp()
            os.write(fd, b"clean data 1\n")
            os.close(fd)
            attempts.append((path,))
            attempts.append(())
            try:
                for args in attempts:
                    try:
                        obj(*args)
                        invoked.append(name)
                        break
                    except TypeError:
                        continue
                    except Exception:
                        # A parser may legitimately reject this input; reaching a
                        # non-signature parser error still proves it was executed.
                        invoked.append(name)
                        break
            finally:
                os.unlink(path)
        print(json.dumps({"origin": origin, "suffix_ok": suffix_ok,
                          "callables": callables, "invoked": invoked}))
    ''')
    result = subprocess.run(
        [PYTHON_BIN, "-c", probe], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, result.stdout + result.stderr
    info = json.loads(result.stdout.strip().splitlines()[-1])
    assert info["suffix_ok"], f"tlv_parser is not a compiled extension: {info['origin']}"
    assert info["callables"], "tlv_parser exposes no deserialization callable"
    assert info["invoked"], "No tlv_parser deserialization callable could be executed"


def test_adversarial_corpus():
    assert os.path.isfile(SANITIZER_SCRIPT), f"{SANITIZER_SCRIPT} does not exist."
    assert os.path.isfile(PYTHON_BIN), f"{PYTHON_BIN} does not exist."

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS_DIR}"
    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS_DIR}"

    evil_bypassed = []
    for evil_file in evil_files:
        result = run_sanitizer(evil_file)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_rejected = []
    for clean_file in clean_files:
        result = run_sanitizer(clean_file)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_corpus_results_are_not_based_on_labeled_paths(tmp_path):
    cases = []
    for directory, expected in ((EVIL_CORPUS_DIR, 1), (CLEAN_CORPUS_DIR, 0)):
        for name in os.listdir(directory):
            source = os.path.join(directory, name)
            if os.path.isfile(source):
                target = tmp_path / secrets.token_hex(16)
                shutil.copyfile(source, target)
                cases.append((str(target), expected))

    for path, expected in cases:
        result = run_sanitizer(path)
        assert result.returncode == expected, (
            f"Sanitizer returned {result.returncode} instead of {expected} for "
            "a corpus payload placed at an unlabeled path."
        )


def test_dynamic_cycle_depth_and_malformed_analysis_uses_parser(tmp_path):
    fake_dir = tmp_path / "injected"
    fake_dir.mkdir()
    log_path = tmp_path / "parser_calls.log"

    case_specs = [
        ("clean", 0),
        ("cycle", 1),
        ("deep", 1),
        ("malformed", 1),
    ]
    cases = []
    digest_kinds = {}
    for kind, expected in case_specs:
        payload = secrets.token_bytes(79)
        path = tmp_path / secrets.token_hex(18)
        path.write_bytes(payload)
        digest_kinds[hashlib.sha256(payload).hexdigest()] = kind
        cases.append((path, expected))

    fake_module = f'''
import hashlib
import os

_KINDS = {digest_kinds!r}
_LOG = os.environ["TLV_TEST_LOG"]


def _content(args):
    for arg in args:
        if isinstance(arg, (bytes, bytearray, memoryview)):
            return bytes(arg)
        if isinstance(arg, (str, os.PathLike)) and os.path.isfile(arg):
            with open(arg, "rb") as f:
                return f.read()
        if hasattr(arg, "read"):
            value = arg.read()
            return value.encode() if isinstance(value, str) else bytes(value)
    return b""


def _parse(*args, **kwargs):
    data = _content(args) or _content(tuple(kwargs.values()))
    kind = _KINDS.get(hashlib.sha256(data).hexdigest())
    with open(_LOG, "a", encoding="utf-8") as f:
        f.write(str(kind) + "\\n")
    if kind == "malformed":
        raise ValueError("malformed TLV")
    if kind == "cycle":
        node = []
        node.append(node)
        return node
    if kind == "deep":
        node = "leaf"
        for _ in range(15):
            node = [node]
        return node
    if kind == "clean":
        return {{"telemetry": [1, 2, {{"value": "safe"}}]}}
    raise ValueError("unknown TLV payload")

parse = _parse
parse_tlv = _parse
deserialize = _parse
loads = _parse
load = _parse
parse_file = _parse
deserialize_file = _parse


def __getattr__(name):
    if name.startswith("__"):
        raise AttributeError(name)
    return _parse
'''
    (fake_dir / "tlv_parser.py").write_text(fake_module)

    env = os.environ.copy()
    env["PYTHONPATH"] = str(fake_dir)
    env["TLV_TEST_LOG"] = str(log_path)

    for path, expected in cases:
        result = run_sanitizer(str(path), env=env)
        assert result.returncode == expected, (
            f"Dynamic structural case {path.name} returned {result.returncode}, "
            f"expected {expected}. stderr={result.stderr.decode(errors='replace')}"
        )

    calls = log_path.read_text().splitlines() if log_path.exists() else []
    assert calls.count("clean") >= 1, "sanitizer did not deserialize the clean payload with tlv_parser"
    assert calls.count("cycle") >= 1, "sanitizer did not deserialize the cyclic payload with tlv_parser"
    assert calls.count("deep") >= 1, "sanitizer did not deserialize the deep payload with tlv_parser"
    assert calls.count("malformed") >= 1, "sanitizer did not pass malformed data to tlv_parser"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
