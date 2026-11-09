#!/bin/bash
set -e
mkdir -p /logs/verifier

if (
    set -e
    RELEASE=/home/user/release

    # Preserve the agent-visible release inputs while exercising build.sh on a
    # verifier-generated fixture whose patch names and RPC names are unpredictable.
    BACKUP=$(mktemp -d)
    cp -a "$RELEASE/base.proto" "$BACKUP/base.proto"
    cp -a "$RELEASE/manifest.txt" "$BACKUP/manifest.txt"
    cp -a "$RELEASE/patches" "$BACKUP/patches"

    test -f "$RELEASE/build.sh"
    test -x "$RELEASE/build.sh"

    TOKEN=$(python3 -c 'import secrets; print(secrets.token_hex(6))')
    export TOKEN
    python3 - <<'PY'
import difflib
import json
import os
from pathlib import Path

release = Path('/home/user/release')
token = os.environ['TOKEN']
patches = release / 'patches'
if patches.exists():
    for p in patches.iterdir():
        if p.is_file() or p.is_symlink():
            p.unlink()
        elif p.is_dir():
            import shutil
            shutil.rmtree(p)
else:
    patches.mkdir()

rpc_a = f'Alpha_{token}'
rpc_b = f'Beta_{token}'
rpc_c = f'Gamma_{token}'
rpc_bad = f'Forbidden_{token}'

base = f'''syntax = "proto3";
package dynamic_{token};

service CoreService {{
}}
'''
state_a = f'''syntax = "proto3";
package dynamic_{token};

service CoreService {{
  rpc {rpc_a} (RequestA) returns (ResponseA);
}}

message RequestA {{}}
message ResponseA {{}}
'''
state_b = f'''syntax = "proto3";
package dynamic_{token};

service CoreService {{
  rpc {rpc_a} (RequestA) returns (ResponseA);
  rpc {rpc_b} (RequestB) returns (ResponseB);
}}

message RequestA {{}}
message ResponseA {{}}
message RequestB {{}}
message ResponseB {{}}
'''
state_c = f'''syntax = "proto3";
package dynamic_{token};

service CoreService {{
  rpc {rpc_a} (RequestA) returns (ResponseA);
  rpc {rpc_b} (RequestB) returns (ResponseB);
  rpc {rpc_c} (RequestC) returns (ResponseC);
}}

message RequestA {{}}
message ResponseA {{}}
message RequestB {{}}
message ResponseB {{}}
message RequestC {{}}
message ResponseC {{}}
'''
bad_state = state_c.replace(
    f'  rpc {rpc_c} (RequestC) returns (ResponseC);',
    f'  rpc {rpc_c} (RequestC) returns (ResponseC);\n  rpc {rpc_bad} (BadRequest) returns (BadResponse);'
) + '\nmessage BadRequest {}\nmessage BadResponse {}\n'

names = {
    '1.2.0': f'a_{token}.patch',
    '1.3.0': f'b_{token}.patch',
    '1.10.0': f'c_{token}.patch',
    '1.10.1': f'above_{token}.patch',
    '1.0.0': f'floor_{token}.patch',
}

def write_patch(name, before, after):
    text = ''.join(difflib.unified_diff(
        before.splitlines(True), after.splitlines(True),
        fromfile='final.proto', tofile='final.proto'))
    (patches / name).write_text(text)

write_patch(names['1.2.0'], base, state_a)
write_patch(names['1.3.0'], state_a, state_b)
write_patch(names['1.10.0'], state_b, state_c)
write_patch(names['1.10.1'], state_c, bad_state)
write_patch(names['1.0.0'], state_c, bad_state)

release.joinpath('base.proto').write_text(base)
release.joinpath('manifest.txt').write_text(
    f"1.10.1=patches/{names['1.10.1']}\n"
    f"1.10.0=patches/{names['1.10.0']}\n"
    f"1.0.0=patches/{names['1.0.0']}\n"
    f"1.3.0=patches/{names['1.3.0']}\n"
    f"1.2.0=patches/{names['1.2.0']}\n"
)
Path('/tmp/dynamic_expected.proto').write_text(state_c)
Path('/tmp/dynamic_expected.json').write_text(json.dumps({
    'log': [
        f"patches/{names['1.2.0']}",
        f"patches/{names['1.3.0']}",
        f"patches/{names['1.10.0']}",
    ],
    'methods': [rpc_a, rpc_b, rpc_c],
    'forbidden': rpc_bad,
}))
PY

    # Remove all products, including the alleged venv, so build.sh must really
    # create the environment, install grpcio-tools, patch, and invoke protoc.
    rm -rf "$RELEASE/final.proto" "$RELEASE/applied_patches.log" \
           "$RELEASE/out" "$RELEASE/venv"
    timeout 300 runuser -u user -- env HOME=/home/user \
        bash -c 'cd /home/user/release && ./build.sh 1.10.0'

    "$RELEASE/venv/bin/python" - <<'PY'
import importlib.metadata
import importlib.util
import json
import py_compile
import sys
from pathlib import Path

release = Path('/home/user/release')
meta = json.loads(Path('/tmp/dynamic_expected.json').read_text())
assert release.joinpath('final.proto').read_text() == Path('/tmp/dynamic_expected.proto').read_text()
lines = [x.strip() for x in release.joinpath('applied_patches.log').read_text().splitlines() if x.strip()]
assert lines == meta['log'], (lines, meta['log'])
assert release.joinpath('venv/pyvenv.cfg').is_file()
assert importlib.metadata.version('grpcio-tools')
import grpc_tools  # noqa: F401

pb2 = release / 'out/final_pb2.py'
pb2_grpc = release / 'out/final_pb2_grpc.py'
assert pb2.is_file() and pb2.stat().st_size > 0
assert pb2_grpc.is_file() and pb2_grpc.stat().st_size > 0
py_compile.compile(str(pb2), doraise=True)
py_compile.compile(str(pb2_grpc), doraise=True)
sys.path.insert(0, str(pb2.parent))
spec = importlib.util.spec_from_file_location('dynamic_final_pb2', pb2)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
service = module.DESCRIPTOR.services_by_name['CoreService']
methods = [m.name for m in service.methods]
assert methods == meta['methods'], (methods, meta['methods'])
assert meta['forbidden'] not in methods
PY

    # Restore the supplied release inputs and execute the exact required target.
    cp -a "$BACKUP/base.proto" "$RELEASE/base.proto"
    cp -a "$BACKUP/manifest.txt" "$RELEASE/manifest.txt"
    rm -rf "$RELEASE/patches"
    cp -a "$BACKUP/patches" "$RELEASE/patches"
    chown -R user:user "$RELEASE/base.proto" "$RELEASE/manifest.txt" "$RELEASE/patches"
    rm -rf "$RELEASE/final.proto" "$RELEASE/applied_patches.log" "$RELEASE/out"
    timeout 300 runuser -u user -- env HOME=/home/user \
        bash -c 'cd /home/user/release && ./build.sh 2.0.0'

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import py_compile
import sys


def test_build_script_exists_and_executable():
    script_path = "/home/user/release/build.sh"
    assert os.path.isfile(script_path), f"Build script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Build script {script_path} is not executable."


def test_applied_patches_log():
    log_path = "/home/user/release/applied_patches.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = [
        "patches/add_health.patch",
        "patches/add_metrics.patch",
        "patches/remove_ping.patch"
    ]
    assert lines == expected_lines, f"Expected: {expected_lines}; got: {lines}"


def test_final_proto_content():
    proto_path = "/home/user/release/final.proto"
    assert os.path.isfile(proto_path), f"Generated {proto_path} is missing."
    with open(proto_path, "r") as f:
        content = f.read()
    assert "rpc HealthCheck" in content
    assert "rpc GetMetrics" in content
    assert "rpc Ping" not in content
    assert "rpc LogEvent" not in content


def test_grpc_output_files():
    out_dir = "/home/user/release/out"
    assert os.path.isdir(out_dir), f"Output directory {out_dir} is missing."
    pb2_file = os.path.join(out_dir, "final_pb2.py")
    pb2_grpc_file = os.path.join(out_dir, "final_pb2_grpc.py")
    assert os.path.isfile(pb2_file), f"gRPC generated file {pb2_file} is missing."
    assert os.path.isfile(pb2_grpc_file), f"gRPC generated file {pb2_grpc_file} is missing."
    assert os.path.getsize(pb2_file) > 0
    assert os.path.getsize(pb2_grpc_file) > 0
    py_compile.compile(pb2_file, doraise=True)
    py_compile.compile(pb2_grpc_file, doraise=True)


def test_generated_descriptor_is_valid():
    out_dir = "/home/user/release/out"
    pb2_file = os.path.join(out_dir, "final_pb2.py")
    sys.path.insert(0, out_dir)
    spec = importlib.util.spec_from_file_location("verified_final_pb2", pb2_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    service = module.DESCRIPTOR.services_by_name["CoreService"]
    methods = [method.name for method in service.methods]
    assert methods == ["HealthCheck", "GetMetrics"]


def test_venv_exists():
    venv_dir = "/home/user/release/venv"
    assert os.path.isdir(venv_dir), f"Virtual environment directory {venv_dir} is missing."
    python_path = os.path.join(venv_dir, "bin", "python")
    assert os.path.isfile(python_path) or os.path.islink(python_path)
    assert os.path.isfile(os.path.join(venv_dir, "pyvenv.cfg"))
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
