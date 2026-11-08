#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import secrets
import subprocess
import sys
import tempfile
import time
import uuid


def test_build_and_test_script_execution():
    script_path = "/home/user/compat/build_and_test.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=300)
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\n"
        f"Stderr: {result.stderr}"
    )


def test_integration_log_contents():
    log_path = "/home/user/compat/integration.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["True", "False", "True"]
    assert lines == expected, f"Expected log contents to be {expected}, but got {lines}."


def test_generated_protos_exist():
    pb2_path = "/home/user/compat/server/compat_pb2.py"
    pb2_grpc_path = "/home/user/compat/server/compat_pb2_grpc.py"

    assert os.path.exists(pb2_path), f"Generated protobuf file {pb2_path} does not exist."
    assert os.path.exists(pb2_grpc_path), f"Generated gRPC file {pb2_grpc_path} does not exist."


def test_semver_tests_pass():
    test_file = "/home/user/compat/tests/test_semver.py"
    assert os.path.exists(test_file), f"Test file {test_file} does not exist."

    result = subprocess.run(["pytest", test_file], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, (
        f"pytest failed for {test_file}.\n"
        f"Stdout: {result.stdout}\n"
        f"Stderr: {result.stderr}"
    )


def test_proto_file_exists():
    proto_path = "/home/user/compat/proto/compat.proto"
    assert os.path.exists(proto_path), f"Protobuf definition {proto_path} does not exist."


def test_python_source_files_exist():
    semver_path = "/home/user/compat/server/semver.py"
    main_path = "/home/user/compat/server/main.py"

    assert os.path.exists(semver_path), f"Source file {semver_path} does not exist."
    assert os.path.exists(main_path), f"Source file {main_path} does not exist."


def test_proto_schema_is_correct():
    from google.protobuf import descriptor_pb2

    proto_dir = "/home/user/compat/proto"
    with tempfile.TemporaryDirectory() as out:
        descriptor_path = os.path.join(out, "schema.pb")
        result = subprocess.run(
            [sys.executable, "-m", "grpc_tools.protoc", f"-I{proto_dir}",
             f"--descriptor_set_out={descriptor_path}", "compat.proto"],
            cwd=proto_dir, capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, result.stderr

        descriptor_set = descriptor_pb2.FileDescriptorSet()
        with open(descriptor_path, "rb") as f:
            descriptor_set.ParseFromString(f.read())

    assert len(descriptor_set.file) == 1
    fd = descriptor_set.file[0]
    assert fd.syntax == "proto3"
    messages = {m.name: m for m in fd.message_type}
    assert "VersionRequest" in messages
    assert "VersionResponse" in messages

    request_fields = {f.name: f for f in messages["VersionRequest"].field}
    assert request_fields["component_name"].number == 1
    assert request_fields["component_name"].type == request_fields["component_name"].TYPE_STRING
    assert request_fields["reported_version"].number == 2
    assert request_fields["reported_version"].type == request_fields["reported_version"].TYPE_STRING

    response_fields = {f.name: f for f in messages["VersionResponse"].field}
    assert response_fields["is_compatible"].number == 1
    assert response_fields["is_compatible"].type == response_fields["is_compatible"].TYPE_BOOL

    services = {s.name: s for s in fd.service}
    assert "CompatibilityDaemon" in services
    methods = {m.name: m for m in services["CompatibilityDaemon"].method}
    assert "CheckVersion" in methods
    method = methods["CheckVersion"]
    assert method.input_type.endswith(".VersionRequest")
    assert method.output_type.endswith(".VersionResponse")


def _load_semver_module():
    path = "/home/user/compat/server/semver.py"
    spec = importlib.util.spec_from_file_location("submitted_semver", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_semver_implementation_on_independent_cases():
    semver_path = "/home/user/compat/server/semver.py"
    source = open(semver_path, encoding="utf-8").read()
    tree = ast.parse(source)
    forbidden = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            forbidden.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            forbidden.add(node.module.split(".")[0])
    assert not ({"semver", "packaging"} & forbidden), "Semantic versions must be parsed from scratch"

    module = _load_semver_module()
    assert callable(getattr(module, "evaluate_version", None))
    evaluate = module.evaluate_version
    rng = secrets.SystemRandom()

    operators = {
        ">=": lambda a, b: a >= b,
        "<=": lambda a, b: a <= b,
        "==": lambda a, b: a == b,
    }
    for _ in range(80):
        reported_tuple = tuple(rng.randrange(0, 40) for _ in range(3))
        reported = ".".join(map(str, reported_tuple))
        conditions = []
        expected = True
        for _ in range(rng.choice((1, 2))):
            op = rng.choice(tuple(operators))
            target_tuple = tuple(rng.randrange(0, 40) for _ in range(3))
            target = ".".join(map(str, target_tuple))
            conditions.append(f"{op} {target}")
            expected = expected and operators[op](reported_tuple, target_tuple)
        constraint = " ".join(conditions)
        actual = evaluate(reported, constraint)
        assert actual is expected, f"evaluate_version({reported!r}, {constraint!r}) returned {actual!r}"

    boundary_cases = [
        ("1.2.0", ">= 1.2.0 <= 1.5.0", True),
        ("1.5.0", ">= 1.2.0 <= 1.5.0", True),
        ("1.5.1", ">= 1.2.0 <= 1.5.0", False),
        ("2.0.1", "== 2.0.1", True),
        ("2.0.0", "== 2.0.1", False),
        ("14.0.0", ">= 14.0.0", True),
    ]
    for reported, constraint, expected in boundary_cases:
        assert evaluate(reported, constraint) is expected


def test_live_grpc_server_with_independent_dynamic_requests():
    import grpc

    proto_dir = "/home/user/compat/proto"
    with tempfile.TemporaryDirectory() as generated:
        result = subprocess.run(
            [sys.executable, "-m", "grpc_tools.protoc", f"-I{proto_dir}",
             f"--python_out={generated}", f"--grpc_python_out={generated}", "compat.proto"],
            cwd=proto_dir, capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, result.stderr

        old_path = list(sys.path)
        old_pb2 = sys.modules.pop("compat_pb2", None)
        old_pb2_grpc = sys.modules.pop("compat_pb2_grpc", None)
        sys.path.insert(0, generated)
        try:
            import compat_pb2
            import compat_pb2_grpc

            env = os.environ.copy()
            env["PYTHONPATH"] = "/home/user/compat/server" + os.pathsep + env.get("PYTHONPATH", "")
            process = subprocess.Popen(
                [sys.executable, "/home/user/compat/server/main.py"],
                cwd="/home/user/compat/server", env=env,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            channel = grpc.insecure_channel("127.0.0.1:50051")
            try:
                grpc.channel_ready_future(channel).result(timeout=15)
                assert process.poll() is None, "main.py exited instead of serving requests"
                stub = compat_pb2_grpc.CompatibilityDaemonStub(channel)
                rng = secrets.SystemRandom()
                inside_minor = rng.randrange(2, 6)
                inside_patch = rng.randrange(0, 100)
                high_minor = rng.randrange(6, 30)
                db_major = rng.randrange(14, 40)
                cases = [
                    ("frontend", f"1.{inside_minor}.{inside_patch}", True),
                    ("frontend", f"1.{high_minor}.{rng.randrange(100)}", False),
                    ("frontend", f"0.{rng.randrange(100)}.{rng.randrange(100)}", False),
                    ("frontend", "1.2.0", True),
                    ("frontend", "1.5.0", True),
                    ("backend", "2.0.1", True),
                    ("backend", f"2.0.{rng.randrange(2, 100)}", False),
                    ("database", f"{db_major}.{rng.randrange(100)}.{rng.randrange(100)}", True),
                    ("database", f"13.{rng.randrange(100)}.{rng.randrange(100)}", False),
                    ("unknown-" + uuid.uuid4().hex, f"{rng.randrange(50)}.{rng.randrange(50)}.{rng.randrange(50)}", False),
                ]
                for component, version, expected in cases:
                    response = stub.CheckVersion(
                        compat_pb2.VersionRequest(component_name=component, reported_version=version),
                        timeout=5,
                    )
                    assert response.is_compatible is expected, (
                        f"CheckVersion({component!r}, {version!r}) returned "
                        f"{response.is_compatible!r}, expected {expected!r}"
                    )
                assert process.poll() is None, "server exited while handling requests"
            finally:
                channel.close()
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
        finally:
            sys.path[:] = old_path
            sys.modules.pop("compat_pb2", None)
            sys.modules.pop("compat_pb2_grpc", None)
            if old_pb2 is not None:
                sys.modules["compat_pb2"] = old_pb2
            if old_pb2_grpc is not None:
                sys.modules["compat_pb2_grpc"] = old_pb2_grpc
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
