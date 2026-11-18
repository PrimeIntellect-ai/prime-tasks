#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import random
import secrets
import shutil
import subprocess
import sys
import sysconfig
from pathlib import Path

SERVICE_DIR = Path("/home/user/math_service")


def load_python_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_repaired_service_end_to_end():
    assert (SERVICE_DIR / "setup.py").is_file(), "setup.py is missing"
    assert (SERVICE_DIR / "fast_math.pyx").is_file(), "fast_math.pyx is missing"
    assert (SERVICE_DIR / "parser.py").is_file(), "parser.py is missing"
    assert (SERVICE_DIR / "service.py").is_file(), "service.py is missing"
    assert (SERVICE_DIR / "test_service.py").is_file(), "test_service.py is missing"

    # Force a clean rebuild so pre-existing generated files cannot satisfy the check.
    shutil.rmtree(SERVICE_DIR / "build", ignore_errors=True)
    (SERVICE_DIR / "fast_math.c").unlink(missing_ok=True)
    for candidate in SERVICE_DIR.glob("fast_math*.so"):
        candidate.unlink()

    build = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=SERVICE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, f"Cython extension build failed:\n{build.stdout}"
    assert (SERVICE_DIR / "fast_math.c").is_file(), "Build did not generate fast_math.c"

    suffix = sysconfig.get_config_var("EXT_SUFFIX")
    extensions = list(SERVICE_DIR.glob(f"fast_math*{suffix}")) if suffix else []
    assert extensions, "Build did not produce an in-place fast_math extension module"

    spec = importlib.util.spec_from_file_location("fast_math", extensions[0])
    assert spec is not None and spec.loader is not None
    fast_math = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fast_math)
    for _ in range(8):
        a = (secrets.randbelow(2_000_001) - 1_000_000) / 113.0
        b = (secrets.randbelow(2_000_001) - 1_000_000) / 127.0
        assert math.isclose(fast_math.fast_add(a, b), a + b, rel_tol=1e-12, abs_tol=1e-12)

    parser_module = load_python_module("submitted_parser", SERVICE_DIR / "parser.py")
    fixed_cases = [
        ("12.5, 14.2, ", [12.5, 14.2]),
        ("  1.0,\t2.5, , 3.14,   ", [1.0, 2.5, 3.14]),
        (", , -7.25, 6e2, ,", [-7.25, 600.0]),
        (" , , ", []),
    ]
    for line, expected in fixed_cases:
        assert parser_module.parse_line(line) == expected

    rng = random.Random(secrets.randbits(128))
    for _ in range(20):
        tokens = [f"{rng.uniform(-10000, 10000):.8f}" for _ in range(rng.randint(1, 12))]
        fields = []
        for token in tokens:
            fields.extend([" " * rng.randint(0, 3), f"{' ' * rng.randint(0, 3)}{token}{' ' * rng.randint(0, 3)}"])
        fields.extend(["", "   "])
        line = ",".join(fields)
        assert parser_module.parse_line(line) == [float(token) for token in tokens]

    service_module = load_python_module("submitted_service", SERVICE_DIR / "service.py")
    for _ in range(8):
        window_size = secrets.randbelow(100) + 1
        count = window_size + secrets.randbelow(500) + 500
        rp = service_module.RollingProcessor(window_size=window_size)
        values = [secrets.randbelow(2_000_001) - 1_000_000 for _ in range(count)]
        for value in values:
            rp.process(value)
        assert len(rp.history) <= window_size, "Rolling history exceeds its configured window"
        assert list(rp.history) == values[-window_size:], "Rolling history does not retain the most recent values"

    rp = service_module.RollingProcessor(window_size=10)
    for i in range(10000):
        rp.process(i)
    assert len(rp.history) <= 10, "History grows during long-running processing"
    assert list(rp.history) == list(range(9990, 10000))

    # Run the supplied test from a clean log state, as required by the task.
    log_path = SERVICE_DIR / "success.log"
    log_path.unlink(missing_ok=True)
    supplied = subprocess.run(
        [sys.executable, "test_service.py"],
        cwd=SERVICE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert supplied.returncode == 0, f"test_service.py failed:\n{supplied.stdout}"

    # Preserve the original verifier assertions.
    assert os.path.exists(log_path), (
        f"The success log was not found at {log_path}. "
        "Ensure you have run `python3 test_service.py` after fixing all issues."
    )
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "PASS" in content, (
        f"The success log at {log_path} does not contain 'PASS'. "
        "The tests in test_service.py might have failed or not completed successfully."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
