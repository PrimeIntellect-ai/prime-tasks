#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import socket
import subprocess
import time
import uuid

PROJECT = '/home/user/project'
GO_SERVER = os.path.join(PROJECT, 'go_server')


def run(cmd, cwd=None, timeout=180):
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nexit={result.returncode}\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return result


def load_groups(path):
    assert os.path.isfile(path), f"{path} does not exist"
    with open(path, 'r') as f:
        data = json.load(f)
    assert isinstance(data, dict), "JSON response must be an object"
    groups = data.get('groups', [])
    assert isinstance(groups, list), "groups must be a list"
    return groups


def groups_by_hash(groups):
    result = {}
    for group in groups:
        assert isinstance(group, dict), f"Invalid duplicate group: {group!r}"
        digest = group.get('hash')
        paths = group.get('file_paths')
        assert isinstance(digest, str), f"Group has no string hash: {group!r}"
        assert isinstance(paths, list), f"Group has no file_paths list: {group!r}"
        assert all(isinstance(p, str) for p in paths), f"Invalid file path list: {paths!r}"
        assert paths == sorted(paths), f"file_paths are not alphabetically sorted: {paths!r}"
        assert digest not in result, f"Duplicate response group for hash {digest}"
        result[digest] = paths
    return result


def make_fixture(root):
    os.makedirs(os.path.join(root, 'nested', 'deeper'), exist_ok=True)
    token = uuid.uuid4().hex.encode()
    common = b'common-' + token + os.urandom(13)
    exact15 = b'X' * 14 + os.urandom(1)
    too_small = b'Y' * 13 + os.urandom(1)
    unique = b'unique-' + os.urandom(41)

    files = {
        'zeta.bin': common,
        'nested/alpha.bin': common,
        'nested/deeper/middle.bin': common,
        'fifteen-b.bin': exact15,
        'nested/fifteen-a.bin': exact15,
        'small-a.bin': too_small,
        'nested/small-b.bin': too_small,
        'only-one.bin': unique,
    }
    for relative, content in files.items():
        path = os.path.join(root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(content)

    return {
        hashlib.sha256(common).hexdigest(): sorted([
            os.path.join(root, 'zeta.bin'),
            os.path.join(root, 'nested/alpha.bin'),
            os.path.join(root, 'nested/deeper/middle.bin'),
        ]),
        hashlib.sha256(exact15).hexdigest(): sorted([
            os.path.join(root, 'fifteen-b.bin'),
            os.path.join(root, 'nested/fifteen-a.bin'),
        ]),
    }


def test_run_sh_exists_and_executable():
    run_sh_path = '/home/user/project/run.sh'
    assert os.path.isfile(run_sh_path), f"{run_sh_path} does not exist"
    assert os.access(run_sh_path, os.X_OK), f"{run_sh_path} is not executable"


def test_execute_run_sh():
    run_sh_path = '/home/user/project/run.sh'
    result = subprocess.run(
        [run_sh_path], cwd='/home/user/project', capture_output=True, text=True, timeout=240
    )
    assert result.returncode == 0, (
        f"run.sh failed with exit code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def test_duplicates_json_correctness():
    json_path = '/home/user/project/duplicates.json'
    assert os.path.isfile(json_path), f"{json_path} does not exist. Did the client generate it?"

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            assert False, f"Failed to parse {json_path} as JSON: {e}"

    groups = data.get('groups', [])
    assert len(groups) == 1, f"Expected exactly 1 duplicate group, got {len(groups)}"

    group = groups[0]
    paths = sorted(group.get('file_paths', []))

    expected_paths = sorted([
        "/home/user/project/test_data/file1.txt",
        "/home/user/project/test_data/file2.txt",
        "/home/user/project/test_data/subdir/file3.txt"
    ])

    assert paths == expected_paths, f"Expected duplicate paths to be {expected_paths}, got {paths}"

    not_expected = [
        "/home/user/project/test_data/file4.txt",
        "/home/user/project/test_data/file5.txt",
        "/home/user/project/test_data/subdir/file6.txt"
    ]
    for p in not_expected:
        assert p not in paths, f"File {p} should not be in the duplicate group"


def test_required_files_exist():
    expected_files = [
        '/home/user/project/proto/fileorg.proto',
        '/home/user/project/go_server/main.go',
        '/home/user/project/go_server/server_test.go',
        '/home/user/project/client/main.go'
    ]
    for f in expected_files:
        assert os.path.isfile(f), f"Required file {f} is missing"

    pb_dir = '/home/user/project/go_server/pb'
    generated = [name for name in os.listdir(pb_dir) if name.endswith('.pb.go')]
    assert generated, f"No generated protobuf Go files found in {pb_dir}"


def test_submitted_go_tests_execute():
    result = run(['go', 'test', '-json', './...'], cwd=GO_SERVER, timeout=240)
    records = []
    for line in result.stdout.splitlines():
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    assert any(r.get('Test', '').startswith('Test') for r in records), (
        'go test succeeded, but server_test.go did not execute any Go test function'
    )


def test_proto_schema():
    descriptor = '/tmp/fileorg-verifier-descriptor.pb'
    run([
        'protoc',
        '-I', os.path.join(PROJECT, 'proto'),
        '--include_imports',
        f'--descriptor_set_out={descriptor}',
        os.path.join(PROJECT, 'proto', 'fileorg.proto'),
    ])

    check_dir = os.path.join(GO_SERVER, '.verifier_descriptor')
    os.makedirs(check_dir, exist_ok=True)
    checker = r'''package main
import (
    "fmt"
    "os"
    "google.golang.org/protobuf/proto"
    "google.golang.org/protobuf/types/descriptorpb"
)
func fail(s string) { fmt.Fprintln(os.Stderr, s); os.Exit(1) }
func field(m *descriptorpb.DescriptorProto, name string) *descriptorpb.FieldDescriptorProto {
    for _, f := range m.Field { if f.GetName() == name { return f } }
    return nil
}
func main() {
    raw, err := os.ReadFile(os.Args[1]); if err != nil { panic(err) }
    set := &descriptorpb.FileDescriptorSet{}
    if err := proto.Unmarshal(raw, set); err != nil { panic(err) }
    var fd *descriptorpb.FileDescriptorProto
    for _, f := range set.File { if f.GetPackage() == "fileorg" { fd = f; break } }
    if fd == nil { fail("protobuf package fileorg was not found") }
    messages := map[string]*descriptorpb.DescriptorProto{}
    for _, m := range fd.MessageType { messages[m.GetName()] = m }
    req, resp, group := messages["DuplicateRequest"], messages["DuplicateResponse"], messages["DuplicateGroup"]
    if req == nil || resp == nil || group == nil { fail("required messages are missing") }
    if len(req.Field) != 1 { fail("DuplicateRequest must contain exactly one field") }
    f := field(req, "directory_path")
    if f == nil || f.GetType() != descriptorpb.FieldDescriptorProto_TYPE_STRING || f.GetLabel() == descriptorpb.FieldDescriptorProto_LABEL_REPEATED { fail("directory_path must be a single string") }
    f = field(resp, "groups")
    if f == nil || f.GetType() != descriptorpb.FieldDescriptorProto_TYPE_MESSAGE || f.GetTypeName() != ".fileorg.DuplicateGroup" || f.GetLabel() != descriptorpb.FieldDescriptorProto_LABEL_REPEATED { fail("groups must be repeated DuplicateGroup") }
    f = field(group, "hash")
    if f == nil || f.GetType() != descriptorpb.FieldDescriptorProto_TYPE_STRING || f.GetLabel() == descriptorpb.FieldDescriptorProto_LABEL_REPEATED { fail("hash must be a single string") }
    f = field(group, "file_paths")
    if f == nil || f.GetType() != descriptorpb.FieldDescriptorProto_TYPE_STRING || f.GetLabel() != descriptorpb.FieldDescriptorProto_LABEL_REPEATED { fail("file_paths must be repeated string") }
    var svc *descriptorpb.ServiceDescriptorProto
    for _, s := range fd.Service { if s.GetName() == "FileOrganizer" { svc = s } }
    if svc == nil { fail("FileOrganizer service is missing") }
    for _, m := range svc.Method {
        if m.GetName() == "FindDuplicates" && m.GetInputType() == ".fileorg.DuplicateRequest" && m.GetOutputType() == ".fileorg.DuplicateResponse" { return }
    }
    fail("FindDuplicates RPC has the wrong request or response type")
}
'''
    with open(os.path.join(check_dir, 'main.go'), 'w') as f:
        f.write(checker)
    run(['go', 'run', './.verifier_descriptor', descriptor], cwd=GO_SERVER, timeout=180)


def test_real_grpc_server_and_client_on_runtime_data():
    rpc_dir = os.path.join(GO_SERVER, '.verifier_rpc_client')
    os.makedirs(rpc_dir, exist_ok=True)
    rpc_source = r'''package main
import (
    "context"
    "encoding/json"
    "fmt"
    "os"
    "time"
    "fileorg/pb"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)
type group struct { Hash string `json:"hash"`; FilePaths []string `json:"file_paths"` }
type output struct { Groups []group `json:"groups"` }
func main() {
    if len(os.Args) != 2 { panic("directory argument required") }
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second); defer cancel()
    conn, err := grpc.DialContext(ctx, "localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithBlock())
    if err != nil { panic(err) }
    defer conn.Close()
    response, err := pb.NewFileOrganizerClient(conn).FindDuplicates(ctx, &pb.DuplicateRequest{DirectoryPath: os.Args[1]})
    if err != nil { panic(err) }
    out := output{}
    for _, g := range response.GetGroups() { out.Groups = append(out.Groups, group{Hash: g.GetHash(), FilePaths: g.GetFilePaths()}) }
    data, err := json.Marshal(out); if err != nil { panic(err) }
    fmt.Print(string(data))
}
'''
    with open(os.path.join(rpc_dir, 'main.go'), 'w') as f:
        f.write(rpc_source)

    run(['go', 'build', '-o', '/tmp/verifier-fileorg-server', '.'], cwd=GO_SERVER, timeout=240)
    run(['go', 'build', '-o', '/tmp/verifier-rpc-client', './.verifier_rpc_client'], cwd=GO_SERVER, timeout=240)
    run(['go', 'build', '-o', '/tmp/verifier-submitted-client', '../client/main.go'], cwd=GO_SERVER, timeout=240)

    server = subprocess.Popen(
        ['/tmp/verifier-fileorg-server'], cwd=GO_SERVER,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    try:
        deadline = time.time() + 15
        while time.time() < deadline:
            if server.poll() is not None:
                out, err = server.communicate()
                assert False, f"Server exited before accepting connections.\nSTDOUT:{out}\nSTDERR:{err}"
            try:
                with socket.create_connection(('127.0.0.1', 50051), timeout=0.25):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            assert False, 'Go server did not listen on localhost:50051'

        fixture = os.path.join('/tmp', 'fileorg-fixture-' + uuid.uuid4().hex)
        expected = make_fixture(fixture)
        result = run(['/tmp/verifier-rpc-client', fixture], timeout=30)
        actual = groups_by_hash(json.loads(result.stdout).get('groups', []))
        assert actual == expected, f"Unexpected gRPC result. Expected {expected}, got {actual}"

        test_data = os.path.join(PROJECT, 'test_data')
        backup = os.path.join('/tmp', 'test-data-backup-' + uuid.uuid4().hex)
        os.rename(test_data, backup)
        try:
            expected_client = make_fixture(test_data)
            output_path = os.path.join(PROJECT, 'duplicates.json')
            if os.path.exists(output_path):
                os.remove(output_path)
            run(['/tmp/verifier-submitted-client'], cwd=PROJECT, timeout=30)
            actual_client = groups_by_hash(load_groups(output_path))
            assert actual_client == expected_client, (
                f"Standalone client did not write the live gRPC response. "
                f"Expected {expected_client}, got {actual_client}"
            )
        finally:
            shutil.rmtree(test_data, ignore_errors=True)
            os.rename(backup, test_data)

        run(['/tmp/verifier-submitted-client'], cwd=PROJECT, timeout=30)
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
