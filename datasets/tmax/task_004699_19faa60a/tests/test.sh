#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_main_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path/filepath"
    "strconv"
)

func main() {
    filename := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), filename, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
    if f.Name.Name != "main" {
        fmt.Fprintln(os.Stderr, "main.go must declare package main")
        os.Exit(1)
    }

    aliases := map[string]string{}
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil {
            continue
        }
        alias := filepath.Base(p)
        if imp.Name != nil {
            alias = imp.Name.Name
        }
        aliases[alias] = p
    }

    hasMain := false
    hasEmbedding := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.FuncDecl:
            if x.Recv == nil && x.Name.Name == "main" {
                hasMain = true
            }
        case *ast.StructType:
            for _, field := range x.Fields.List {
                if len(field.Names) != 0 {
                    continue
                }
                typ := field.Type
                if ptr, ok := typ.(*ast.StarExpr); ok {
                    typ = ptr.X
                }
                sel, ok := typ.(*ast.SelectorExpr)
                if !ok || sel.Sel.Name != "UnimplementedDataProcessorServer" {
                    continue
                }
                id, ok := sel.X.(*ast.Ident)
                if ok && aliases[id.Name] == "pipeline/api" {
                    hasEmbedding = true
                }
            }
        }
        return true
    })

    if !hasMain {
        fmt.Fprintln(os.Stderr, "main.go has no main function")
        os.Exit(1)
    }
    if !hasEmbedding {
        fmt.Fprintln(os.Stderr, "no struct embeds pipeline/api.UnimplementedDataProcessorServer")
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

PIPELINE = "/home/user/pipeline"
PROTOS = "/home/user/protos"
EXPECTED_VERSION = "2.0.1"
EXPECTED_LOG = "Successfully built service version 2.0.1"


def run(cmd, cwd=None, env=None):
    result = subprocess.run(cmd, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert result.returncode == 0, result.stdout
    return result.stdout


def semver_key(version):
    m = re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?", version)
    assert m, f"Invalid semantic version in proto filename: {version}"
    prerelease = m.group(4)
    parts = []
    if prerelease is not None:
        for item in prerelease.split("."):
            parts.append((0, int(item)) if item.isdigit() else (1, item))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), prerelease is None, parts)


def highest_proto():
    found = []
    for name in os.listdir(PROTOS):
        m = re.fullmatch(r"service_(.+)\.proto", name)
        if m:
            found.append((semver_key(m.group(1)), m.group(1), name))
    assert found, "No service_<version>.proto files found"
    return max(found, key=lambda item: item[0])


def plugin_env():
    env = os.environ.copy()
    gopath = run(["go", "env", "GOPATH"]).strip().split(os.pathsep)[0]
    env["PATH"] = env.get("PATH", "") + os.pathsep + os.path.join(gopath, "bin")
    return env


def test_highest_semantic_version():
    _, version, name = highest_proto()
    assert version == EXPECTED_VERSION
    assert name == "service_2.0.1.proto"


def test_success_log_exists_and_content():
    log_path = "/home/user/pipeline/success.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_LOG, f"Expected '{EXPECTED_LOG}' in {log_path}, got '{content}'"


def test_generated_go_files_exist():
    pb_go = "/home/user/pipeline/api/service_2.0.1.pb.go"
    grpc_pb_go = "/home/user/pipeline/api/service_2.0.1_grpc.pb.go"
    assert os.path.isfile(pb_go), f"Generated file {pb_go} is missing."
    assert os.path.isfile(grpc_pb_go), f"Generated file {grpc_pb_go} is missing."


def test_other_versions_not_compiled():
    api_dir = "/home/user/pipeline/api"
    if not os.path.isdir(api_dir):
        return
    files = os.listdir(api_dir)
    invalid_versions = ["1.5.9", "1.12.0", "2.0.1-rc.1"]
    for v in invalid_versions:
        pb_go = f"service_{v}.pb.go"
        grpc_pb_go = f"service_{v}_grpc.pb.go"
        assert pb_go not in files, f"File {pb_go} should not have been generated."
        assert grpc_pb_go not in files, f"File {grpc_pb_go} should not have been generated."


def test_plugins_and_generated_code_match_protoc_output():
    env = plugin_env()
    assert shutil.which("protoc-gen-go", path=env["PATH"]), "protoc-gen-go is not installed"
    assert shutil.which("protoc-gen-go-grpc", path=env["PATH"]), "protoc-gen-go-grpc is not installed"

    _, version, proto_name = highest_proto()
    expected_names = {f"service_{version}.pb.go", f"service_{version}_grpc.pb.go"}
    generated_names = {
        name for name in os.listdir(os.path.join(PIPELINE, "api"))
        if re.fullmatch(r"service_.+(?:_grpc)?\.pb\.go", name)
        or re.fullmatch(r"service_.+_grpc\.pb\.go", name)
    }
    assert generated_names == expected_names, f"Expected only {expected_names}, got {generated_names}"

    with tempfile.TemporaryDirectory() as tmp:
        run([
            "protoc", "-I", ".",
            f"--go_out={tmp}", "--go_opt=module=pipeline",
            f"--go-grpc_out={tmp}", "--go-grpc_opt=module=pipeline",
            proto_name,
        ], cwd=PROTOS, env=env)
        for name in expected_names:
            submitted = os.path.join(PIPELINE, "api", name)
            reference = os.path.join(tmp, "api", name)
            assert os.path.isfile(reference), f"protoc did not generate {reference}"
            with open(submitted, "rb") as a, open(reference, "rb") as b:
                assert a.read() == b.read(), f"{submitted} is not the code generated from {proto_name}"


def test_go_module_main_embedding_build_and_execution():
    gomod = os.path.join(PIPELINE, "go.mod")
    main_go = os.path.join(PIPELINE, "main.go")
    assert os.path.isfile(gomod), "go.mod is missing"
    assert os.path.isfile(main_go), "main.go is missing"
    with open(gomod) as f:
        module_text = f.read()
    assert re.search(r"(?m)^module\s+pipeline\s*$", module_text), "go.mod module must be pipeline"

    checker = "/tmp/check_main_ast"
    env = plugin_env()
    checker_env = env.copy()
    checker_env["GO111MODULE"] = "off"
    run(["go", "build", "-o", checker, "/tmp/check_main_ast.go"], cwd="/tmp", env=checker_env)
    run([checker, main_go])

    assert run(["go", "list", "-m"], cwd=PIPELINE, env=env).strip() == "pipeline"
    binary = "/tmp/pipeline_submission"
    run(["go", "build", "-o", binary, "."], cwd=PIPELINE, env=env)

    log_path = os.path.join(PIPELINE, "success.log")
    if os.path.exists(log_path):
        os.remove(log_path)
    run([binary], cwd=PIPELINE, env=env)
    assert os.path.isfile(log_path), "Running the built program did not create success.log"
    with open(log_path) as f:
        content = f.read().strip()
    assert content == EXPECTED_LOG, f"Built program wrote {content!r}, expected {EXPECTED_LOG!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
