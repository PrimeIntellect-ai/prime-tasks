#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import os
import runpy
import secrets
import subprocess
import tempfile
import uuid

import numpy as np

HOME = "/home/user"
CSV = os.path.join(HOME, "transactions.csv")


def run_pipeline(env=None):
    return subprocess.run(
        [os.path.join(HOME, "pipeline.sh")],
        cwd=HOME,
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )


def expected_ci(amounts):
    np.random.seed(42)
    values = np.asarray(amounts, dtype=float)
    means = [np.mean(np.random.choice(values, size=len(values), replace=True)) for _ in range(1000)]
    lower, upper = np.percentile(means, [2.5, 97.5])
    return f"{lower:.2f},{upper:.2f}"


def write_dataset(amounts):
    with open(CSV, "w", newline="") as f:
        f.write("transaction_id,amount,category\n")
        for i, amount in enumerate(amounts, 1):
            f.write(f"{i},{amount:.4f},C{i % 5}\n")


def assert_decodable_nonblank_png(path):
    assert os.path.isfile(path), "plot.png was not generated"
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "plot.png is not a valid PNG file"
    assert len(data) > 1000, "plot.png is unexpectedly small"
    import matplotlib.image as mpimg
    image = mpimg.imread(path)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
    assert float(np.var(image)) > 0.0, "plot.png is blank"
    return hashlib.sha256(data).hexdigest()


def test_scripts_exist():
    assert os.path.isfile("/home/user/validate.sh"), "validate.sh is missing"
    assert os.path.isfile("/home/user/bootstrap.py"), "bootstrap.py is missing"
    assert os.path.isfile("/home/user/pipeline.sh"), "pipeline.sh is missing"


def test_scripts_executable():
    assert os.access("/home/user/validate.sh", os.X_OK), "validate.sh is not executable"
    assert os.access("/home/user/pipeline.sh", os.X_OK), "pipeline.sh is not executable"


def test_pipeline_execution_and_outputs():
    result = run_pipeline()
    assert result.returncode == 0, f"pipeline.sh failed with exit code {result.returncode}\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    assert os.path.isfile("/home/user/ci.txt"), "ci.txt was not generated"
    with open("/home/user/ci.txt", "r") as f:
        ci_content = f.read().strip()
    assert ci_content == "94.70,117.70", f"ci.txt content is incorrect. Expected '94.70,117.70', got '{ci_content}'"

    assert os.path.isfile("/home/user/plot.png"), "plot.png was not generated"
    with open("/home/user/plot.png", "rb") as f:
        header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", "plot.png is not a valid PNG file"


def test_validate_sh_bad_csv():
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        tmp.write("transaction_id,amount,category\n")
        tmp.write("1,100\n")
        tmp_path = tmp.name
    try:
        result = subprocess.run(["/home/user/validate.sh", tmp_path], capture_output=True)
        assert result.returncode == 1, "validate.sh should exit with status 1 for an invalid CSV"
    finally:
        os.remove(tmp_path)


def test_validate_sh_bad_header():
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        tmp.write("id,amount,category\n")
        tmp.write("1,100,A\n")
        tmp_path = tmp.name
    try:
        result = subprocess.run(["/home/user/validate.sh", tmp_path], capture_output=True)
        assert result.returncode == 1, "validate.sh should exit with status 1 for an invalid header"
    finally:
        os.remove(tmp_path)


def test_validate_sh_general_schema_enforcement():
    rng = secrets.SystemRandom()
    cases = []

    for _ in range(6):
        rows = rng.randint(1, 15)
        content = "transaction_id,amount,category\n"
        for i in range(rows):
            content += f"{uuid.uuid4().hex},{rng.randint(-100000, 100000)},K{rng.randint(1, 99)}\n"
        cases.append((content, 0))

    bad_header = f"{uuid.uuid4().hex},amount,category\n1,10,A\n"
    cases.append((bad_header, 1))
    cases.append(("transaction_id,amount,category\n1,10\n2,20,A\n", 1))
    cases.append(("transaction_id,amount,category\n1,10,A,EXTRA\n", 1))
    cases.append(("transaction_id,amount,category\n1\n", 1))
    cases.append(("transaction_id,amount,category\n1,10,A\n\n2,20,B\n", 1))
    cases.append(("transaction_id,amount,category,extra\n1,10,A,foo\n", 1))
    rng.shuffle(cases)

    for content, expected in cases:
        fd, path = tempfile.mkstemp(prefix="schema_", suffix=".csv")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(content)
            result = subprocess.run([os.path.join(HOME, "validate.sh"), path], capture_output=True)
            assert result.returncode == expected, f"validate.sh returned {result.returncode}, expected {expected}, for {content!r}"
        finally:
            os.remove(path)


def test_bootstrap_uses_required_numpy_sampling_calls():
    original_csv = open(CSV, "rb").read()
    original_seed = np.random.seed
    original_choice = np.random.choice
    seed_calls = []
    choice_calls = []
    rng = secrets.SystemRandom()
    amounts = [round(rng.uniform(-700, 1300), 4) for _ in range(rng.randint(17, 43))]

    def seed_wrapper(*args, **kwargs):
        seed_calls.append((args, kwargs))
        return original_seed(*args, **kwargs)

    def choice_wrapper(a, *args, **kwargs):
        result = original_choice(a, *args, **kwargs)
        if "replace" in kwargs:
            replace = kwargs["replace"]
        elif len(args) >= 2:
            replace = args[1]
        else:
            replace = True
        choice_calls.append((np.asarray(result).size, bool(replace)))
        return result

    try:
        write_dataset(amounts)
        np.random.seed = seed_wrapper
        np.random.choice = choice_wrapper
        runpy.run_path(os.path.join(HOME, "bootstrap.py"), run_name="__main__")
    finally:
        np.random.seed = original_seed
        np.random.choice = original_choice
        with open(CSV, "wb") as f:
            f.write(original_csv)

    assert any(call[0] and call[0][0] == 42 for call in seed_calls), "bootstrap.py did not call numpy.random.seed(42)"
    assert len(choice_calls) == 1000, f"expected 1000 numpy.random.choice calls, got {len(choice_calls)}"
    assert all(size == len(amounts) for size, _ in choice_calls), "bootstrap sample size must equal the number of data rows"
    assert all(replace for _, replace in choice_calls), "bootstrap samples must use replacement"


def test_backend_is_configured_before_pyplot_import():
    source = open(os.path.join(HOME, "bootstrap.py"), "r").read()
    tree = ast.parse(source)
    pyplot_lines = []
    backend_lines = []

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name.startswith("matplotlib.pyplot") for alias in node.names):
                pyplot_lines.append(node.lineno)
        elif isinstance(node, ast.ImportFrom):
            if node.module == "matplotlib" and any(alias.name == "pyplot" for alias in node.names):
                pyplot_lines.append(node.lineno)
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "use":
            if node.args and isinstance(node.args[0], ast.Constant) and str(node.args[0].value).lower() == "agg":
                backend_lines.append(node.lineno)
        elif isinstance(node, ast.Assign):
            if isinstance(node.value, ast.Constant) and str(node.value.value).lower() == "agg":
                for target in node.targets:
                    if isinstance(target, ast.Subscript):
                        key = target.slice
                        if isinstance(key, ast.Constant) and key.value == "MPLBACKEND":
                            backend_lines.append(node.lineno)

    assert pyplot_lines, "bootstrap.py does not import matplotlib pyplot"
    assert backend_lines and min(backend_lines) < min(pyplot_lines), "the Agg backend must be explicitly configured before importing pyplot"


def test_pipeline_on_unpredictable_datasets_and_real_plots():
    original_csv = open(CSV, "rb").read()
    rng = secrets.SystemRandom()
    hashes = []
    try:
        for _ in range(3):
            amounts = [round(rng.uniform(-2500, 5000), 4) for _ in range(rng.randint(13, 61))]
            write_dataset(amounts)
            for output in ("ci.txt", "plot.png"):
                path = os.path.join(HOME, output)
                if os.path.exists(path):
                    os.remove(path)

            env = os.environ.copy()
            env["MPLBACKEND"] = "module://backend_that_does_not_exist"
            result = run_pipeline(env=env)
            assert result.returncode == 0, f"pipeline failed on a valid generated dataset\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

            with open(os.path.join(HOME, "ci.txt")) as f:
                actual = f.read().strip()
            expected = expected_ci(amounts)
            assert actual == expected, f"generated-data CI mismatch: expected {expected}, got {actual}"
            hashes.append(assert_decodable_nonblank_png(os.path.join(HOME, "plot.png")))
    finally:
        with open(CSV, "wb") as f:
            f.write(original_csv)

    assert len(set(hashes)) == len(hashes), "plot.png did not change when the bootstrap data changed"


def test_pipeline_stops_when_generated_input_is_invalid():
    original_csv = open(CSV, "rb").read()
    marker = uuid.uuid4().hex
    try:
        with open(CSV, "w") as f:
            f.write("transaction_id,amount,category\n")
            f.write(f"{marker},123\n")
        for output in ("ci.txt", "plot.png"):
            path = os.path.join(HOME, output)
            if os.path.exists(path):
                os.remove(path)

        result = run_pipeline()
        assert result.returncode == 1, "pipeline.sh must exit with status 1 when validation fails"
        assert "Validation failed" in result.stdout, "pipeline.sh must print 'Validation failed'"
        assert not os.path.exists(os.path.join(HOME, "ci.txt")), "bootstrap.py ran despite failed validation"
        assert not os.path.exists(os.path.join(HOME, "plot.png")), "bootstrap.py ran despite failed validation"
    finally:
        with open(CSV, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
