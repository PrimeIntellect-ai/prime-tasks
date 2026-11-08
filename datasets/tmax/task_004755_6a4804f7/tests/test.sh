#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import os
import secrets
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

ENTRY_POINT = "/home/user/run_detector.sh"
PROJECT_DIR = Path("/home/user")
LIB_DIR = PROJECT_DIR / "libtrajectory"
LIB_PATH = LIB_DIR / "libtrajectory.so"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
BUILT_DETECTOR = Path("/tmp/verifier_detector")


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 60)
    return subprocess.run(cmd, **kwargs)


@pytest.fixture(scope="session", autouse=True)
def build_artifacts():
    assert (LIB_DIR / "Makefile").is_file(), "C library Makefile is missing."
    result = run(["make", "-B"], cwd=LIB_DIR)
    assert result.returncode == 0, f"C library does not rebuild successfully:\n{result.stdout}\n{result.stderr}"
    assert LIB_PATH.is_file(), "libtrajectory.so was not built."

    assert (PROJECT_DIR / "detector.go").is_file(), "detector.go is missing."
    assert (PROJECT_DIR / "go.mod").is_file(), "go.mod is missing."
    env = os.environ.copy()
    env["CGO_ENABLED"] = "1"
    result = run(["go", "build", "-o", str(BUILT_DETECTOR), "."], cwd=PROJECT_DIR, env=env)
    assert result.returncode == 0, f"Go detector does not build with cgo enabled:\n{result.stdout}\n{result.stderr}"
    yield
    BUILT_DETECTOR.unlink(missing_ok=True)


def detector_env(extra_library_dir=None):
    env = os.environ.copy()
    dirs = []
    if extra_library_dir is not None:
        dirs.append(str(extra_library_dir))
    dirs.append(str(LIB_DIR))
    if env.get("LD_LIBRARY_PATH"):
        dirs.append(env["LD_LIBRARY_PATH"])
    env["LD_LIBRARY_PATH"] = ":".join(dirs)
    return env


def invoke(program, path, env=None):
    return run([str(program), str(path)], env=env or detector_env())


def test_entry_point_exists_and_executable():
    assert os.path.isfile(ENTRY_POINT), f"Entry point script {ENTRY_POINT} does not exist."
    st = os.stat(ENTRY_POINT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Entry point script {ENTRY_POINT} is not executable."


def test_corpora_classification():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}"

    clean_rejected = []
    for fpath in clean_files:
        result = invoke(ENTRY_POINT, fpath)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(fpath))

    evil_bypassed = []
    for fpath in evil_files:
        result = invoke(ENTRY_POINT, fpath)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(fpath))

    errors = []
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_randomized_unseen_trajectories():
    rng = secrets.SystemRandom()
    valid_steps = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1), (2, 0), (-2, 0), (0, 2), (0, -2)]

    with tempfile.TemporaryDirectory(prefix="trajectory_cases_") as td:
        cases = []
        for should_be_clean in ([True, False] * 10):
            x, y = rng.randint(-5000, 5000), rng.randint(-5000, 5000)
            points = [(x, y)]
            count = rng.randint(3, 10)
            bad_index = rng.randrange(count - 1) if not should_be_clean else -1
            for i in range(count - 1):
                if i == bad_index:
                    dx, dy = rng.choice([(3, 0), (-3, 0), (0, 3), (0, -3), (3, 4), (-4, 3), (7, -2)])
                else:
                    dx, dy = rng.choice(valid_steps)
                x, y = x + dx, y + dy
                points.append((x, y))

            path = Path(td) / f"{secrets.token_hex(12)}.dat"
            path.write_text("".join(f"{px},{py}\n" for px, py in points))
            cases.append((path, should_be_clean))

        rng.shuffle(cases)
        for path, should_be_clean in cases:
            result = invoke(ENTRY_POINT, path)
            if should_be_clean:
                assert result.returncode == 0, f"Unseen valid trajectory was rejected: {path.name}"
            else:
                assert result.returncode != 0, f"Unseen impossible trajectory was accepted: {path.name}"


def test_wrapper_requires_exactly_one_argument():
    clean = next(iter(glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))))
    assert run([ENTRY_POINT], env=detector_env()).returncode != 0, "Wrapper accepted zero arguments."
    assert run([ENTRY_POINT, clean, clean], env=detector_env()).returncode != 0, "Wrapper accepted more than one argument."


def test_libtrajectory_so_exists():
    assert os.path.isfile("/home/user/libtrajectory/libtrajectory.so"), "libtrajectory.so was not built."


def test_library_is_valid_shared_object_with_visible_api():
    header = run(["readelf", "-h", str(LIB_PATH)])
    assert header.returncode == 0, f"libtrajectory.so is not a readable ELF file: {header.stderr}"
    assert "DYN (Shared object file)" in header.stdout, "libtrajectory.so is not an ELF shared object."

    symbols = run(["nm", "-D", "--defined-only", "--format=posix", str(LIB_PATH)])
    assert symbols.returncode == 0, f"Cannot inspect library ABI: {symbols.stderr}"
    exported = set()
    for line in symbols.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[1].upper() in {"T", "D", "B", "R", "G", "S"}:
            exported.add(fields[0].split("@@", 1)[0].split("@", 1)[0])
    assert "check_trajectory" in exported, "check_trajectory is not exported by the shared-library ABI."
    unexpected = exported - {"check_trajectory", "_init", "_fini"}
    assert not unexpected, f"Internal implementation symbols are exposed in the ABI: {sorted(unexpected)}"

    lib = ctypes.CDLL(str(LIB_PATH))
    check = lib.check_trajectory
    check.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    check.restype = ctypes.c_int
    assert check(0, 0, 1, 1) != 0
    assert check(-20, 7, -18, 7) != 0
    assert check(0, 0, 2, 1) == 0
    assert check(100, -100, 100, -103) == 0


def test_go_sources_use_cgo_and_concurrency():
    analyzer = r'''package main
import (
  "fmt"
  "go/ast"
  "go/parser"
  "go/token"
  "os"
  "path/filepath"
  "strconv"
  "strings"
)
func main() {
  dir := os.Args[1]
  fset := token.NewFileSet()
  pkgs, err := parser.ParseDir(fset, dir, func(info os.FileInfo) bool {
    return strings.HasSuffix(info.Name(), ".go") && !strings.HasSuffix(info.Name(), "_test.go")
  }, 0)
  if err != nil { panic(err) }
  hasC, hasGo, hasChan, hasGRPC := false, false, false, false
  for _, pkg := range pkgs { for _, f := range pkg.Files {
    for _, imp := range f.Imports {
      p, _ := strconv.Unquote(imp.Path.Value)
      if p == "C" { hasC = true }
      if strings.Contains(p, "grpc") { hasGRPC = true }
    }
    ast.Inspect(f, func(n ast.Node) bool {
      switch n.(type) {
      case *ast.GoStmt: hasGo = true
      case *ast.ChanType: hasChan = true
      }
      return true
    })
  }}
  if !hasC || !(hasGRPC || (hasGo && hasChan)) {
    fmt.Printf("cgo=%v go=%v channel=%v grpc=%v\n", hasC, hasGo, hasChan, hasGRPC)
    os.Exit(1)
  }
}
'''
    analyzer_path = Path("/tmp/check_detector_ast.go")
    analyzer_path.write_text(analyzer)
    result = run(["go", "run", str(analyzer_path), str(PROJECT_DIR)], cwd="/tmp")
    assert result.returncode == 0, "Go implementation must import C and implement either gRPC or a goroutine/channel worker pool. " + result.stdout + result.stderr

    dynamic = run(["readelf", "-d", str(BUILT_DETECTOR)])
    assert dynamic.returncode == 0, f"Cannot inspect built Go detector: {dynamic.stderr}"
    assert "libtrajectory" in dynamic.stdout, "Built Go detector is not dynamically linked to libtrajectory.so."


def test_go_program_and_wrapper_actually_use_c_library():
    with tempfile.TemporaryDirectory(prefix="cgo_probe_") as td:
        td = Path(td)
        trajectory = td / f"{secrets.token_hex(10)}.txt"
        trajectory.write_text(f"{secrets.randbelow(1000)},{secrets.randbelow(1000)}\n1,1\n")
        # Replace the content so the step is certainly valid while retaining an unpredictable file.
        x, y = secrets.randbelow(1000), secrets.randbelow(1000)
        trajectory.write_text(f"{x},{y}\n{x + 1},{y}\n")

        assert invoke(BUILT_DETECTOR, trajectory).returncode == 0, "Built Go detector rejected a valid trajectory."
        assert invoke(ENTRY_POINT, trajectory).returncode == 0, "Wrapper rejected a valid trajectory."

        trap_c = td / "trajectory.c"
        trap_c.write_text("__attribute__((visibility(\"default\"))) int check_trajectory(int x1,int y1,int x2,int y2){(void)x1;(void)y1;(void)x2;(void)y2;return 0;}\n")
        trap_so = td / "libtrajectory.so"
        compiled = run(["gcc", "-shared", "-fPIC", "-Wl,-soname,libtrajectory.so", "-o", str(trap_so), str(trap_c)])
        assert compiled.returncode == 0, compiled.stderr
        env = detector_env(td)

        assert invoke(BUILT_DETECTOR, trajectory, env=env).returncode != 0, "Go detector behavior did not depend on check_trajectory from the C library."
        assert invoke(ENTRY_POINT, trajectory, env=env).returncode != 0, "run_detector.sh does not invoke the Go/cgo detector path."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
