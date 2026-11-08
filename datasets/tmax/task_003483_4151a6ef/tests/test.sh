#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import shlex
import shutil
import subprocess
import tempfile
import uuid


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=30, **kwargs)


def test_evaluate_script():
    path = "/home/user/evaluate.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "r") as f:
        content = f.read()
    assert "artifact_info.env" in content, f"{path} must source artifact_info.env"


def test_benchmark_script():
    path = "/home/user/benchmark.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "r") as f:
        content = f.read()
    assert "evaluate.sh" in content, f"{path} must call evaluate.sh"
    assert "expressions.txt" in content, f"{path} must read expressions.txt"


def _without_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def _named_block(text, kind, name):
    match = re.search(rf"\b{re.escape(kind)}\s+{re.escape(name)}\s*\{{", text)
    assert match, f"Missing {kind} {name} block"
    depth = 1
    i = match.end()
    start = i
    in_string = False
    escaped = False
    while i < len(text):
        ch = text[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start:i]
        i += 1
    raise AssertionError(f"Unclosed {kind} {name} block")


def test_evaluator_proto():
    path = "/home/user/evaluator.proto"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert re.search(r'syntax\s*=\s*"proto3"\s*;', content), "Missing or incorrect syntax declaration in proto file."
    assert re.search(r'service\s+ArtifactEvaluator\s*\{', content), "Missing service ArtifactEvaluator in proto file."
    assert re.search(r'rpc\s+Evaluate\s*\(\s*EvaluationRequest\s*\)\s*returns\s*\(\s*EvaluationResponse\s*\)', content), "Missing or incorrect rpc Evaluate in proto file."
    assert re.search(r'message\s+EvaluationRequest\s*\{', content), "Missing message EvaluationRequest in proto file."
    assert re.search(r'string\s+expression\s*=', content), "Missing string expression field in EvaluationRequest."
    assert re.search(r'message\s+EvaluationResponse\s*\{', content), "Missing message EvaluationResponse in proto file."
    assert re.search(r'int32\s+result\s*=', content), "Missing int32 result field in EvaluationResponse."

    # Compile the submitted schema so malformed protobuf cannot pass regex checks.
    assert shutil.which("protoc"), "protoc is unavailable in the verifier image"
    with tempfile.TemporaryDirectory() as tempdir:
        descriptor = os.path.join(tempdir, "evaluator.pb")
        proc = run([
            "protoc",
            "--proto_path=/home/user",
            f"--descriptor_set_out={descriptor}",
            "evaluator.proto",
        ], cwd="/home/user")
        assert proc.returncode == 0, f"evaluator.proto does not compile:\n{proc.stderr}"
        assert os.path.isfile(descriptor) and os.path.getsize(descriptor) > 0

    # Ensure the required fields and RPC are inside their intended blocks.
    clean = _without_comments(content)
    request_body = _named_block(clean, "message", "EvaluationRequest").strip()
    response_body = _named_block(clean, "message", "EvaluationResponse").strip()
    service_body = _named_block(clean, "service", "ArtifactEvaluator")

    request_match = re.fullmatch(r"(?:optional\s+)?string\s+expression\s*=\s*(\d+)\s*;", request_body)
    response_match = re.fullmatch(r"(?:optional\s+)?int32\s+result\s*=\s*(\d+)\s*;", response_body)
    assert request_match, "EvaluationRequest must contain the single string field expression"
    assert response_match, "EvaluationResponse must contain the single int32 field result"
    for match in (request_match, response_match):
        number = int(match.group(1))
        assert 1 <= number <= 536870911 and not 19000 <= number <= 19999

    assert re.search(
        r"\brpc\s+Evaluate\s*\(\s*EvaluationRequest\s*\)\s*returns\s*\(\s*EvaluationResponse\s*\)\s*(?:;|\{)",
        service_body,
    ), "Evaluate RPC must be declared inside ArtifactEvaluator"


def test_evaluation_results_log():
    path = "/home/user/evaluation_results.log"
    assert os.path.isfile(path), f"File {path} does not exist. Did you run benchmark.sh?"

    with open(path, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "MAJOR + 2 = 5",
        "MINOR * PATCH = 8",
        "(MAJOR + MINOR) * 2 = 14",
        "BUILD_NUMBER - (MAJOR * 10) = 75"
    ]

    for expected in expected_lines:
        assert any(expected in line for line in content), f"Expected result '{expected}' not found in {path}"


def test_evaluator_behavior_on_derived_inputs():
    evaluator = "/home/user/evaluate.sh"
    env_path = "/home/user/artifact_info.env"
    original_env = open(env_path, "rb").read()
    rng = random.SystemRandom()
    major = rng.randrange(11, 80)
    minor = rng.randrange(3, 20)
    patch = rng.randrange(2, 10)
    dynamic = rng.randrange(101, 500)

    try:
        with open(env_path, "w") as f:
            f.write(f"MAJOR={major}\nMINOR={minor}\nPATCH={patch}\nDYNAMIC_VALUE={dynamic}\nBUILD_NUMBER={major * 20 + minor}\n")

        cases = [
            ("MAJOR + MINOR * PATCH", major + minor * patch),
            ("(MAJOR + MINOR) * PATCH", (major + minor) * patch),
            ("DYNAMIC_VALUE - MAJOR", dynamic - major),
            ("BUILD_NUMBER / PATCH", (major * 20 + minor) // patch),
        ]
        for expression, expected in cases:
            proc = run([evaluator, expression])
            assert proc.returncode == 0, f"evaluate.sh failed for {expression!r}: {proc.stderr}"
            assert re.fullmatch(r"-?\d+\n?", proc.stdout), f"evaluate.sh must print only an integer, got {proc.stdout!r}"
            assert proc.stdout.strip() == str(expected), f"Wrong result for {expression!r}"

        assert run([evaluator]).returncode != 0, "evaluate.sh must reject zero arguments"
        assert run([evaluator, "MAJOR", "MINOR"]).returncode != 0, "evaluate.sh must reject more than one argument"
    finally:
        with open(env_path, "wb") as f:
            f.write(original_env)


def test_benchmark_executes_required_iterations_and_writes_results():
    benchmark = "/home/user/benchmark.sh"
    evaluator = "/home/user/evaluate.sh"
    env_path = "/home/user/artifact_info.env"
    expressions_path = "/home/user/expressions.txt"
    log_path = "/home/user/evaluation_results.log"

    originals = {}
    for path in (env_path, expressions_path, log_path):
        originals[path] = open(path, "rb").read() if os.path.exists(path) else None

    rng = random.SystemRandom()
    major = rng.randrange(10, 60)
    minor = rng.randrange(4, 15)
    patch = rng.randrange(2, 9)
    build = rng.randrange(150, 400)
    constant1 = rng.randrange(17, 70)
    constant2 = rng.randrange(5, 30)
    expressions = [
        f"MAJOR + {constant1}",
        f"MINOR * PATCH - {constant2}",
        "(BUILD_NUMBER - MAJOR) / 2",
    ]
    expected = [
        major + constant1,
        minor * patch - constant2,
        (build - major) // 2,
    ]

    token = uuid.uuid4().hex
    saved_evaluator = f"/tmp/evaluate-original-{token}.sh"
    trace = f"/tmp/evaluate-trace-{token}.log"
    evaluator_mode = os.stat(evaluator).st_mode

    try:
        with open(env_path, "w") as f:
            f.write(f"MAJOR={major}\nMINOR={minor}\nPATCH={patch}\nBUILD_NUMBER={build}\n")
        with open(expressions_path, "w") as f:
            f.write("\n".join(expressions) + "\n")
        with open(log_path, "w"):
            pass

        os.rename(evaluator, saved_evaluator)
        wrapper = f'''#!/bin/bash
printf '%s\\t%s\\n' "$#" "${{1-}}" >> {shlex.quote(trace)}
exec {shlex.quote(saved_evaluator)} "$@"
'''
        with open(evaluator, "w") as f:
            f.write(wrapper)
        os.chmod(evaluator, 0o755)

        proc = run([benchmark])
        assert proc.returncode == 0, f"benchmark.sh failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"

        with open(trace, "r") as f:
            calls = [line.rstrip("\n").split("\t", 1) for line in f]
        assert len(calls) == 101 * len(expressions), "benchmark.sh must invoke evaluate.sh 101 times per expression"
        counts = collections.Counter((argc, expr) for argc, expr in calls)
        assert set(counts) == {("1", expr) for expr in expressions}, "benchmark.sh passed unexpected arguments to evaluate.sh"
        for expression in expressions:
            assert counts[("1", expression)] == 101, f"Expected 101 evaluations of {expression!r}"

        with open(log_path, "r") as f:
            lines = f.read().splitlines()
        wanted = [f"{expression} = {result}" for expression, result in zip(expressions, expected)]
        assert lines == wanted, "evaluation_results.log has incorrect or improperly formatted results"
    finally:
        if os.path.lexists(evaluator):
            os.remove(evaluator)
        if os.path.exists(saved_evaluator):
            os.rename(saved_evaluator, evaluator)
            os.chmod(evaluator, evaluator_mode)
        if os.path.exists(trace):
            os.remove(trace)
        for path, data in originals.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
