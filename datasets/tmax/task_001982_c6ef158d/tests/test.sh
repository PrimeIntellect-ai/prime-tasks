#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import pytest

MUTATOR = "/home/user/mutator"
SIDECAR = {"name": "qemu-vnc", "image": "localhost:5000/qemu-vnc:1.0"}


def test_deployer_env_configured():
    env_path = "/home/user/deployer.env"
    assert os.path.exists(env_path), f"{env_path} does not exist"
    with open(env_path, "r") as f:
        content = f.read()
    assert 'FILTER_CMD="/home/user/mutator"' in content, f'Expected FILTER_CMD="/home/user/mutator" in {env_path}'


def test_deployer_reload_triggered():
    reload_path = "/home/user/deployer.reload"
    assert os.path.exists(reload_path), f"{reload_path} was not created to trigger reload"


def test_mutator_artifacts_exist():
    assert os.path.isfile("/home/user/mutator.go"), "/home/user/mutator.go does not exist"
    assert os.path.isfile(MUTATOR), f"Executable {MUTATOR} does not exist"
    assert os.access(MUTATOR, os.X_OK), f"{MUTATOR} is not executable"


def expected_value(value):
    # Derive the required transformation directly from the specification.
    if isinstance(value, dict) and value.get("kind") == "Pod":
        spec = value.get("spec")
        if isinstance(spec, dict):
            containers = spec.get("containers")
            if isinstance(containers, list):
                for container in containers:
                    if isinstance(container, dict):
                        image = container.get("image")
                        if isinstance(image, str) and image.endswith(":latest"):
                            container["image"] = image[:-7] + ":staged"
                containers.append(dict(SIDECAR))
    return value


def run_case(input_text):
    proc = subprocess.run([MUTATOR], input=input_text.encode(), capture_output=True, timeout=5)
    assert proc.returncode == 0, (
        f"Mutator failed with {proc.returncode} for input {input_text!r}: "
        f"{proc.stderr.decode(errors='replace')}"
    )
    out = proc.stdout
    assert out, f"Mutator produced no output for {input_text!r}"
    assert not out.endswith(b"\n"), "Output has a trailing newline"
    try:
        decoded = out.decode("utf-8")
        actual = json.loads(decoded)
    except Exception as exc:
        pytest.fail(f"Output is not valid UTF-8 JSON for {input_text!r}: {out!r} ({exc})")

    expected = expected_value(json.loads(input_text))
    assert actual == expected, f"Wrong result for {input_text!r}: {actual!r} != {expected!r}"

    # Python's compact encoder gives the required no-extra-whitespace representation.
    assert decoded == json.dumps(actual, ensure_ascii=False, separators=(",", ":")), (
        f"Output is not minified JSON: {decoded!r}"
    )


def test_targeted_cases():
    cases = [
        ' { "kind" : "Service", "items" : [ 1, 2 ], "image" : "x:latest" } ',
        ' [ 1, { "kind" : "Pod", "spec" : { "containers" : [] } }, true, null ] ',
        ' "arbitrary string" ',
        ' 42 ',
        ' true ',
        ' null ',
        '{"kind":"pod","spec":{"containers":[{"image":"x:latest"}]}}',
        '{"kind":"Pod","spec":{"containers":[]}}',
        '{"kind":"Pod","spec":{"containers":[{"name":"a","image":"repo:latest","x":1},{"image":"repo:v1"},7,null,{"image":":latest"}]},"extra":{"z":true}}',
        '{"kind":"Pod","spec":{"containers":"not-an-array"}}',
        '{"kind":"Pod","spec":null}',
        '{"kind":"Pod"}',
    ]
    for case in cases:
        run_case(case)


def random_json(rng, depth=0):
    if depth >= 4:
        return rng.choice([None, True, False, rng.randint(-1000, 1000), "text", ":latest", "réseau"])
    choice = rng.randrange(6)
    if choice == 0:
        return None
    if choice == 1:
        return rng.choice([True, False])
    if choice == 2:
        return rng.randint(-100000, 100000)
    if choice == 3:
        return rng.choice(["", "text", "latest", ":latest", "img:latest", "雪"])
    if choice == 4:
        return [random_json(rng, depth + 1) for _ in range(rng.randrange(5))]
    return {f"k{depth}_{i}": random_json(rng, depth + 1) for i in range(rng.randrange(5))}


def test_derived_random_cases():
    rng = random.Random(918273)
    values = []
    for _ in range(250):
        if rng.random() < 0.55:
            containers = []
            for i in range(rng.randrange(6)):
                if rng.random() < 0.8:
                    image = f"registry/x{i}" + (":latest" if rng.random() < 0.5 else f":v{rng.randrange(9)}")
                    containers.append({"name": f"c{i}", "image": image, "payload": random_json(rng, 3)})
                else:
                    containers.append(random_json(rng, 3))
            values.append({"kind": "Pod", "spec": {"containers": containers, "other": random_json(rng)}, "meta": random_json(rng)})
        else:
            values.append(random_json(rng))

    for value in values:
        # Include whitespace in input while requiring compact output.
        run_case(json.dumps(value, ensure_ascii=False, indent=2))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
