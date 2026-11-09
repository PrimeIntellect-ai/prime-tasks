#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import pathlib
import subprocess
import tempfile

import pytest

TOOL_DIR = pathlib.Path("/app/vendor/secure_etl_tool-1.0")
SO_FILE = TOOL_DIR / "fast_integrity.so"
WORKER = TOOL_DIR / "worker.py"
MAKEFILE = TOOL_DIR / "Makefile"
RESULT = pathlib.Path("/home/user/benchmark_result.txt")
BENCHMARK = pathlib.Path("/home/user/run_benchmark.sh")

EXPECTED_BENCHMARK = '''#!/bin/bash
cd /app/vendor/secure_etl_tool-1.0/

rm -f /tmp/leak_detected

# Start a background process that monitors for leaks
(
    for i in {1..30}; do
        if ps -ef | grep "pass:" | grep -v grep > /dev/null; then
            touch /tmp/leak_detected
        fi
        sleep 0.1
    done
) &
MONITOR_PID=$!

START=$(date +%s.%N)
python3 worker.py
END=$(date +%s.%N)
DUR=$(echo "$END - $START" | bc)

wait $MONITOR_PID

if [ -f /tmp/leak_detected ]; then
    echo "0.0" > /home/user/benchmark_result.txt
else
    # Calculate logs per second
    SCORE=$(echo "5000 / $DUR" | bc -l)
    echo "$SCORE" > /home/user/benchmark_result.txt
fi
'''


def load_and_exercise_extension():
    code = r'''
import importlib.machinery
import pathlib
import fast_integrity
p = pathlib.Path(fast_integrity.__file__).resolve()
expected = pathlib.Path("/app/vendor/secure_etl_tool-1.0/fast_integrity.so").resolve()
assert p == expected, (p, expected)
assert any(str(p).endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), p
assert callable(fast_integrity.verify)
assert fast_integrity.verify() is True
assert fast_integrity.verify(b"sample") is True
assert fast_integrity.verify(None, 123) is True
'''
    completed = subprocess.run(
        ["python3", "-c", code], cwd=TOOL_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr


def test_c_extension_compiled_and_rebuildable():
    assert SO_FILE.is_file(), f"Compiled C-extension {SO_FILE} is missing. Did you fix the Makefile and run make?"
    load_and_exercise_extension()

    make_text = MAKEFILE.read_text()
    assert "/usr/include/python2.7" not in make_text, "Makefile still contains the deliberately incorrect Python 2.7 include path."

    SO_FILE.unlink()
    completed = subprocess.run(
        ["make"], cwd=TOOL_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert SO_FILE.is_file(), "make did not recreate fast_integrity.so"
    load_and_exercise_extension()


def test_worker_patched_no_pass_argument_and_uses_extension():
    assert WORKER.is_file(), f"File {WORKER} is missing."
    content = WORKER.read_text()
    assert content, "worker.py is empty."

    tree = ast.parse(content, filename=str(WORKER))
    imports_extension = any(
        (isinstance(node, ast.Import) and any(alias.name == "fast_integrity" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "fast_integrity")
        for node in ast.walk(tree)
    )
    assert imports_extension, "worker.py does not import the compiled fast_integrity extension."


def test_certificate_configuration():
    config_path = TOOL_DIR / "config.json"
    assert config_path.is_file(), "config.json is missing."
    with config_path.open() as f:
        config = json.load(f)
    assert config.get("cert_path") == "/app/certs/client.pem", "config.json does not point to the required client certificate."
    assert pathlib.Path(config["cert_path"]).is_file(), "Configured client certificate is missing."


def test_benchmark_result_from_real_secure_run():
    assert BENCHMARK.is_file(), f"Benchmark script {BENCHMARK} is missing."
    assert BENCHMARK.read_text() == EXPECTED_BENCHMARK, "Do not modify /home/user/run_benchmark.sh."

    with tempfile.TemporaryDirectory() as fake_bin:
        argv_log = pathlib.Path(fake_bin) / "openssl.argv"
        fake_openssl = pathlib.Path(fake_bin) / "openssl"
        fake_openssl.write_text(
            "#!/bin/bash\n"
            "printf '%s\\0' \"$@\" >> \"$OPENSSL_ARGV_LOG\"\n"
            "sleep 0.5\n"
            "exit 0\n"
        )
        fake_openssl.chmod(0o755)

        try:
            RESULT.unlink()
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env["PATH"] = fake_bin + os.pathsep + env.get("PATH", "")
        env["OPENSSL_ARGV_LOG"] = str(argv_log)
        completed = subprocess.run(
            ["/bin/bash", str(BENCHMARK)], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert completed.returncode == 0, completed.stdout + completed.stderr
        assert argv_log.is_file(), "worker.py did not launch the expected openssl subprocess."

        raw_args = argv_log.read_bytes().split(b"\0")
        args = [arg.decode("utf-8", "replace") for arg in raw_args if arg]
        assert "enc" in args and "-d" in args, f"openssl was not invoked for decryption: {args!r}"
        assert "supersecret" not in args, f"TLS password was exposed as a subprocess argument: {args!r}"
        for arg in args:
            if arg.startswith("pass:"):
                assert arg.startswith("pass:env:") or arg in ("pass:stdin",), \
                    f"A password appears directly in the subprocess command line: {arg!r}"

    assert RESULT.is_file(), f"Benchmark result file {RESULT} is missing. Did you run the benchmark script?"
    content = RESULT.read_text().strip()
    try:
        score = float(content)
    except ValueError:
        pytest.fail(f"Could not parse benchmark score as a float. File content: '{content}'")
    assert score >= 250.0, f"Benchmark score {score} is below the required threshold of 250.0 (Logs processed per second)."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
