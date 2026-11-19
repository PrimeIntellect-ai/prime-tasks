#!/usr/bin/env python3
"""Grade one openai/math challenge with Comparator.

This runs as root in a separate verifier sandbox that never executed agent code. The only input the
agent controls is /logs/artifacts/submission.tar. Everything else comes from /tests (this task's
trusted challenge and Comparator config) and from the image.

Steps:
  1. Unpack submission.tar, accepting only regular `Submission.lean` / `Submission/**.lean` files.
  2. Lay out a fresh Lake project: the trusted lakefile, Challenge.lean from /tests, the submission,
     and the image's prebuilt Mathlib (root-owned, read-only to the grader).
  3. Run `lake env comparator config.json` as the unprivileged `grader` user, with no network.
     Comparator builds Challenge and Submission inside landrun, checks that every listed theorem
     has exactly the challenge's statement, that only the permitted axioms are used, and replays
     the proof through the Lean kernel.
  4. Kill everything the grader started, then write the verdict.

reward.txt is 1 only when Comparator prints its success line and exits 0. A rejected or
non-compiling submission scores 0. A broken grading setup (the trusted Challenge fails to build,
the network block cannot be installed) writes no reward, so Harbor reports an error instead of a
score.

Prime Intellect changes for Prime VM sandboxes, whose guest kernel has neither Landlock nor the
iptables `owner` match: Comparator runs its builds through landrun-bwrap (bubblewrap, same file
system and network policy) instead of landrun, which `check_build_sandbox` verifies before grading;
the grader's network block is the nftables equivalent of the iptables rule, probed against a
listener opened here; and the system-wide open-file limit is raised to what a Lean build needs.
"""

from __future__ import annotations

import json
import os
import pwd
import re
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
from pathlib import Path

TESTS = Path("/tests")
VERIFIER_DIR = Path("/logs/verifier")
SUBMISSION_TAR = Path("/logs/artifacts/submission.tar")
LEAN_ENV = Path("/opt/lean-env")
RUN_ROOT = Path("/var/lib/oai-grade")
GRADER = "grader"
COMPARATOR_LANDRUN = "/usr/local/bin/landrun-bwrap"
NFT_TABLE = "openai_math_grade"
FILE_MAX_PATH, FILE_MAX = Path("/proc/sys/fs/file-max"), 1 << 20
SUCCESS_LINE = "Your solution is okay!"
GRADE_THREADS = "2"
SCRATCH_SWEEP_SEC = 15
# Lake and Comparator wording when a build process is killed for running out of memory.
OOM_MARKERS = ("Lean exited with code 137", "Child exited with 137")

MAX_FILES = 20_000
MAX_FILE_BYTES = 64 << 20
MAX_TOTAL_BYTES = 768 << 20
# Submission.lean, or Submission/A/B.lean where each component is a Lean identifier: it starts with
# a letter or `_` and continues with letters, digits (subscripts like `₁` included), `_`, `'`, `!`, `?`.
# Unicode is allowed because Lean identifiers allow it (openai/math has a module named `Kappa₁`).
_COMPONENT = r"[^\W\d][\w'!?]*"
MEMBER = re.compile(rf"^Submission(?:/{_COMPONENT})*\.lean$")
MEMBER_DIR = re.compile(rf"^Submission(?:/{_COMPONENT})*/?$")

LAKEFILE = """import Lake
open Lake DSL

package openai_math where
  leanOptions := #[⟨`autoImplicit, false⟩]

require mathlib from git
  "https://github.com/leanprover-community/mathlib4.git" @ "d13f23b723b8a846827a245b89c10fc7d3f11612"

lean_lib Challenge

-- `Submission` and every `Submission.*` module it imports.
lean_lib Submission
"""


class Rejected(Exception):
    """The submission is invalid: reward 0."""


class GradingError(Exception):
    """The grading setup is broken: no reward, so the trial shows as errored."""


def toolchain_bin() -> Path:
    bins = sorted(Path("/opt/elan/toolchains").glob("*/bin"))
    if len(bins) != 1:
        raise GradingError(f"expected one Lean toolchain, found {bins}")
    return bins[0]


def unpack_submission(dest: Path) -> dict:
    """Copy the submission's .lean files into ``dest``; reject anything else."""
    try:
        st = SUBMISSION_TAR.lstat()
    except FileNotFoundError:
        raise Rejected("no submission: /workspace/Submission.lean was not found after the agent finished")
    if not SUBMISSION_TAR.is_file() or SUBMISSION_TAR.is_symlink() or st.st_size > MAX_TOTAL_BYTES + (64 << 20):
        raise Rejected("submission archive is not a regular file of acceptable size")

    files, total = [], 0
    try:
        with tarfile.open(SUBMISSION_TAR, "r:") as tar:
            for count, member in enumerate(tar):
                if count > MAX_FILES * 2:
                    raise Rejected(f"submission has more than {MAX_FILES} entries")
                name = member.name.removeprefix("./")
                if member.isdir():
                    if not MEMBER_DIR.match(name):
                        raise Rejected(f"unexpected directory in submission: {name!r}")
                    continue
                if not member.isreg():
                    raise Rejected(f"only regular .lean files are accepted, got {name!r}")
                if not MEMBER.match(name):
                    raise Rejected(f"unexpected file in submission: {name!r} (only Submission.lean and Submission/**.lean)")
                if member.size > MAX_FILE_BYTES:
                    raise Rejected(f"{name} is larger than {MAX_FILE_BYTES >> 20} MB")
                total += member.size
                if total > MAX_TOTAL_BYTES or len(files) >= MAX_FILES:
                    raise Rejected("submission is too large")
                data = tar.extractfile(member).read(MAX_FILE_BYTES + 1)
                try:
                    data.decode("utf-8")
                except UnicodeDecodeError:
                    raise Rejected(f"{name} is not valid UTF-8")
                target = dest / name
                if target.exists():
                    raise Rejected(f"duplicate entry {name!r}")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                target.chmod(0o644)
                files.append(name)
    except tarfile.TarError as exc:
        raise Rejected(f"submission archive is unreadable: {exc}")
    if "Submission.lean" not in files:
        raise Rejected("no submission: /workspace/Submission.lean was not found after the agent finished")
    for d in (dest / "Submission",):
        if d.exists():
            for p in [d, *d.rglob("*")]:
                if p.is_dir():
                    p.chmod(0o755)
    return {"files": len(files), "bytes": total}


def write_project(run: Path, config: dict) -> None:
    (run / "lakefile.lean").write_text(LAKEFILE)
    shutil.copy(LEAN_ENV / "lake-manifest.json", run / "lake-manifest.json")
    shutil.copy(LEAN_ENV / "lean-toolchain", run / "lean-toolchain")
    shutil.copy(TESTS / "Challenge.lean", run / "Challenge.lean")
    comparator_config = {
        "challenge_module": "Challenge",
        "solution_module": "Submission",
        "theorem_names": config["theorem_names"],
        "definition_names": config["definition_names"],
        "permitted_axioms": config["permitted_axioms"],
        "enable_nanoda": False,
    }
    (run / "config.json").write_text(json.dumps(comparator_config, indent=2))
    lake = run / ".lake"
    lake.mkdir()
    (lake / "packages").symlink_to(LEAN_ENV / ".lake" / "packages")
    for p in run.iterdir():
        if p.name != ".lake":
            os.chmod(p, 0o644 if p.is_file() else 0o755, follow_symlinks=False)
    uid = pwd.getpwnam(GRADER).pw_uid
    os.chown(lake, uid, uid)
    os.chmod(run, 0o755)


def fresh_run(task: dict) -> Path:
    """A new, empty Lake project for one grading attempt."""
    run = Path(tempfile.mkdtemp(prefix="run.", dir=RUN_ROOT))
    write_project(run, task["comparator"])
    return run


def ensure_readable(roots: tuple[str, ...] = ("/opt/elan", str(LEAN_ENV))) -> int:
    """Make the prebuilt toolchain and packages readable by the grader (never writable).

    The image already does this; this only repairs an image built without it. It must touch
    nothing that is already right: these files live in the image's lower overlay layer, and a
    `chmod` on one copies it whole into the sandbox's writable layer. A blanket `chmod -R` took
    535 s and used 8.7 GB of the 10 GB working disk. This walk only reads metadata (lstat).
    Returns the number of entries changed.
    """
    changed = 0
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            for name in [*dirnames, *filenames]:
                path = os.path.join(dirpath, name)
                st = os.lstat(path)
                if stat.S_ISDIR(st.st_mode):
                    want = (st.st_mode | 0o555) & ~0o022
                elif stat.S_ISREG(st.st_mode):
                    want = (st.st_mode | 0o444) & ~0o022
                else:
                    continue
                if stat.S_IMODE(st.st_mode) != stat.S_IMODE(want):
                    os.chmod(path, stat.S_IMODE(want))
                    changed += 1
    return changed


def raise_open_file_limit() -> None:
    """Every Lean process opens each imported Mathlib module's .olean files (three per module), so a
    parallel build exceeds the ~98k system-wide open files Prime guests start with."""
    if int(FILE_MAX_PATH.read_text()) < FILE_MAX:
        FILE_MAX_PATH.write_text(f"{FILE_MAX}\n")


def block_grader_network() -> None:
    """Reject every socket the grader user opens, loopback included.

    The build sandbox already has no network. This rule also covers the grader's own processes
    outside it and services listening inside the sandbox (sandboxd on Prime). It is the nftables
    form of `iptables -m owner --uid-owner grader -j REJECT`, which Prime guests cannot load.
    """
    uid = pwd.getpwnam(GRADER).pw_uid
    ruleset = (
        f"table inet {NFT_TABLE}\n"
        f"delete table inet {NFT_TABLE}\n"
        f"table inet {NFT_TABLE} {{\n"
        "  chain output {\n"
        "    type filter hook output priority 0; policy accept;\n"
        f"    meta skuid {uid} reject\n"
        "  }\n"
        "}\n"
    )
    res = subprocess.run(["nft", "-f", "-"], input=ruleset, capture_output=True, text=True)
    if res.returncode != 0:
        raise GradingError(f"cannot install the nftables rule for {GRADER}: {res.stderr.strip()}")
    for family, host in ((socket.AF_INET, "127.0.0.1"), (socket.AF_INET6, "::1")):
        with socket.socket(family) as listener:
            listener.bind((host, 0))
            listener.listen()
            probe = subprocess.run(
                ["runuser", "-u", GRADER, "--", sys.executable, "-c",
                 "import socket,sys\n"
                 f"s=socket.socket({int(family)}); s.settimeout(3)\n"
                 f"sys.exit(3 if s.connect_ex(({host!r}, {listener.getsockname()[1]})) == 0 else 0)"],
                capture_output=True,
            )
        if probe.returncode == 3:
            raise GradingError("the grader user can still open loopback connections")
        if probe.returncode != 0:
            raise GradingError(f"the network probe failed: {probe.stderr.decode(errors='replace')[-500:]}")


# Run as the grader inside landrun-bwrap by `check_build_sandbox`. argv: the run directory.
SANDBOX_PROBE = r"""
import os, socket, sys
run = sys.argv[1]
failures = []
def denied(path):
    try:
        with open(path, "w"):
            pass
    except OSError:
        return True
    os.unlink(path)
    return False
if denied(os.path.join(run, ".lake", ".sandbox-probe")):
    failures.append("cannot write the writable .lake directory")
for path in (os.path.join(run, ".sandbox-probe"), "/tmp/.sandbox-probe", "/var/lib/oai-grade/.sandbox-probe"):
    if not denied(path):
        failures.append(f"could write {path}")
s = socket.socket()
s.settimeout(3)
if s.connect_ex(("1.1.1.1", 443)) == 0:
    failures.append("could open a TCP connection")
pids = [p for p in os.listdir("/proc") if p.isdigit()]
if len(pids) > 3:
    failures.append(f"sees {len(pids)} processes")
print("; ".join(failures))
sys.exit(1 if failures else 0)
"""


def check_build_sandbox(run: Path) -> None:
    """Refuse to grade unless landrun-bwrap confines the grader the way Comparator relies on.

    Comparator gives the builds it runs read-only access to `/`, write access to `.lake` only, no
    network, and (through landrun's Landlock domain) no way to reach processes outside. The probe
    runs as the grader through the same entry point and with the same kind of arguments.
    """
    cmd = [
        "runuser", "-u", GRADER, "--", "env", "-i", "PATH=/usr/local/bin:/usr/bin:/bin",
        COMPARATOR_LANDRUN, "--best-effort", "--ro", "/", "--rw", "/dev", "-ldd", "-add-exec",
        "--env", "PATH", "--ro", str(run), "--rwx", str(run / ".lake"),
        "--", "python3", "-c", SANDBOX_PROBE, str(run),
    ]
    res = subprocess.run(cmd, cwd=run, capture_output=True, text=True, timeout=120)
    if res.returncode != 0:
        raise GradingError(f"the build sandbox check failed: {(res.stdout + res.stderr).strip()[-500:]}")


def kill_grader() -> None:
    for _ in range(20):
        subprocess.run(["pkill", "-9", "-u", GRADER], capture_output=True)
        if subprocess.run(["pgrep", "-u", GRADER], capture_output=True).returncode != 0:
            return
        time.sleep(0.5)
    raise GradingError("could not stop the grader's processes")


def out_of_memory(out: str) -> bool:
    return any(m in out for m in OOM_MARKERS)


def out_of_disk(out: str) -> bool:
    return "no space left on device" in out.lower()


# Run as the grader user by `empty_build_scratch`. argv: the .lake/build/ir directory.
EMPTY_SCRATCH = r"""
import os, sys
for dirpath, _, files in os.walk(sys.argv[1]):
    for name in files:
        if not name.endswith(".setup.json"):
            continue
        base = os.path.join(dirpath, name[:-len(".setup.json")])
        try:
            # Lake writes X.c.hash once Lean, and leanir if the module needs it, are done with X;
            # both read X.setup.json, so it may only be emptied after that.
            if os.stat(base + ".c.hash").st_mtime < os.stat(base + ".setup.json").st_mtime:
                continue
            for path in (base + ".setup.json", base + ".c"):
                if os.path.getsize(path):
                    os.truncate(path, 0)
        except OSError:
            pass
"""


def empty_build_scratch(run: Path, stop: threading.Event) -> None:
    """Until ``stop`` is set, empty files Lake leaves in .lake/build/ir that grading never reads.

    For every module Lake writes a `.setup.json` (its imports with the path of every .olean they
    pull in, about 5.5 MB with Mathlib) and the module compiled to C. Neither is used once the
    module is built, and for proofs of 1,000-2,000 modules they filled the 10 GB disk before the
    build finished. Lake keeps the recorded hashes, so emptied files do not trigger a rebuild.
    This runs as the grader user, so it can touch nothing the build could not.
    """
    ir = str(run / ".lake" / "build" / "ir")
    while not stop.wait(SCRATCH_SWEEP_SEC):
        try:
            subprocess.run(["runuser", "-u", GRADER, "--", sys.executable, "-c", EMPTY_SCRATCH, ir],
                           capture_output=True, timeout=600)
        except subprocess.TimeoutExpired:
            pass


def run_comparator(run: Path, timeout_sec: int, threads: str = GRADE_THREADS) -> tuple[int | None, str]:
    env = {
        "PATH": f"{toolchain_bin()}:/usr/local/bin:/usr/bin:/bin",
        "HOME": str(run),
        "LANG": "C.UTF-8",
        "LEAN_ABORT_ON_PANIC": "1",
        # Lean sees every host CPU, not the sandbox's 4; bound Lake's parallel builds so a large
        # proof fits in 8 GB. Needs the image's Comparator, which passes this into landrun.
        "LEAN_NUM_THREADS": threads,
        "COMPARATOR_LANDRUN": COMPARATOR_LANDRUN,
    }
    cmd = [
        "runuser", "-u", GRADER, "--", "env", "-i", *(f"{k}={v}" for k, v in env.items()),
        "lake", "env", "comparator", "config.json",
    ]
    stop = threading.Event()
    sweeper = threading.Thread(target=empty_build_scratch, args=(run, stop), daemon=True)
    sweeper.start()
    try:
        code, stdout, stderr = run_with_timeout(
            cmd, cwd=run, timeout_sec=timeout_sec,
            kill_extra=lambda: subprocess.run(["pkill", "-9", "-u", GRADER], capture_output=True),
        )
    finally:
        stop.set()
        sweeper.join()
    return code, stdout + "\n--- stderr ---\n" + stderr


def run_with_timeout(cmd: list[str], cwd: Path, timeout_sec: int, kill_extra=None) -> tuple[int | None, str, str]:
    """Run ``cmd``; on timeout kill its whole process tree and return code None.

    `timeout(1)` only signals its direct child, so Lean processes started by Lake under landrun
    kept the output pipe open and the grader waited past Harbor's own limit. Here the command
    gets its own session; on timeout its process group is killed, and ``kill_extra`` (every
    process of the grader user) catches anything that left the group.
    """
    proc = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, errors="replace", start_new_session=True)
    try:
        stdout, stderr = proc.communicate(timeout=timeout_sec)
        return proc.returncode, stdout, stderr
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if kill_extra:
            kill_extra()
        stdout, stderr = proc.communicate()
        return None, stdout, stderr


def classify(code: int | None, out: str) -> tuple[int | None, str]:
    """Map Comparator's result to (reward, reason). reward None means a grading error."""
    if code == 0 and SUCCESS_LINE in out:
        return 1, "accepted: statements match, only permitted axioms, kernel replay passed"
    if "Building Submission" not in out:
        # Comparator stopped before it touched the submission: the trusted challenge or the
        # toolchain is broken (or too slow), which says nothing about the agent's proof.
        return None, ("timed out before the submission was built" if code is None
                      else "the trusted Challenge failed to build or export")
    if code is None:
        return 0, "timed out while building or checking the submission"
    tail = [l for l in out.splitlines() if l.strip() and "has local changes" not in l][-25:]
    if out_of_disk(out):
        return 0, "rejected: the build ran out of disk space (10 GB) | " + " | ".join(tail)[-3000:]
    if out_of_memory(out):
        return 0, "rejected: the build was killed, most likely out of memory (8 GB) | " + " | ".join(tail)[-3000:]
    return 0, "rejected: " + " | ".join(tail)[-4000:]


def main() -> int:
    VERIFIER_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(VERIFIER_DIR, 0o755)
    for name in ("reward.txt", "reward.json"):
        (VERIFIER_DIR / name).unlink(missing_ok=True)

    task = json.loads((TESTS / "task.json").read_text())
    details: dict = {"task": task["challenge"], "started_at": time.time()}
    reward: int | None = None
    log = ""
    try:
        RUN_ROOT.mkdir(mode=0o711, parents=True, exist_ok=True)
        deadline = time.time() + int(task["grade_timeout_sec"])
        run = fresh_run(task)
        details["permission_fixes"] = ensure_readable()
        raise_open_file_limit()
        block_grader_network()
        check_build_sandbox(run)
        details["submission"] = unpack_submission(run)
        code, out = run_comparator(run, int(deadline - time.time()))
        log = out
        kill_grader()
        if code not in (0, None) and out_of_memory(out) and deadline - time.time() > 60:
            # Two Lean processes in parallel can exceed 8 GB on a heavy module. Retry once with one,
            # in a fresh directory: the first attempt's .lake was written by the submission's own
            # build and must not be trusted for the challenge.
            shutil.rmtree(run, ignore_errors=True)
            run = fresh_run(task)
            unpack_submission(run)
            code, out = run_comparator(run, int(deadline - time.time()), threads="1")
            log += "\n\n=== retried with one Lean process after running out of memory ===\n\n" + out
            kill_grader()
            details["retried_single_thread"] = True
        reward, details["reason"] = classify(code, out)
        details["comparator_exit"] = code
    except Rejected as exc:
        reward, details["reason"] = 0, f"rejected: {exc}"
    except GradingError as exc:
        reward, details["reason"] = None, f"grading error: {exc}"
    except Exception as exc:
        reward, details["reason"] = None, f"grading error: {type(exc).__name__}: {exc}"
    finally:
        try:
            kill_grader()
        except GradingError as exc:
            reward, details["reason"] = None, f"grading error: {exc}"
        # Free the build before writing anything. A build that filled the disk would otherwise
        # make these writes fail, and with no space left the sandbox cannot report that the
        # verifier exited, so Harbor waits until its own timeout and records no verdict.
        shutil.rmtree(RUN_ROOT, ignore_errors=True)
    details["reward"] = reward
    details["finished_at"] = time.time()
    (VERIFIER_DIR / "comparator.log").write_text(log)
    (VERIFIER_DIR / "grading.json").write_text(json.dumps(details, indent=2))
    print(json.dumps(details, indent=2))
    if reward is not None:
        (VERIFIER_DIR / "reward.txt").write_text(f"{reward}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
