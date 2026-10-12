"""Model-free QC for openai-math through VF's native, separate-verifier Harbor lifecycle.

Every control is graded by the task's own verifier (tests/grade.py) in a fresh box, exactly as an
agent's submission would be:

  gold    solution/solve.sh places openai/math's own proof, fetched from GitHub  -> reward 1
  empty   no submission                                                           -> reward 0
  attack  upstream's reward-hacking probes (generator/openai_math_harbor/attacks.py) plus a
          Prime-specific process-visibility probe, each placed by its solve.sh    -> reward 0

Prime counts the image toward a sandbox's disk, so --image-disk-gb is added to the tasks' 10 GB, as
the prime-envs taskset does. Evidence goes to <output>/<task>/<control>/ (result.json, grading.json,
comparator.log); a passed result for unchanged task files is reused.

    PRIME_TEAM_ID=<team> uv run --with 'verifiers[harbor]>=0.3.2.dev199' \\
        scripts/openai-math/validate.py --output qc --control gold --concurrency 32
"""

import argparse
import asyncio
import hashlib
import json
import logging
import sys
import tempfile
import time
import traceback
from pathlib import Path

import verifiers.v1 as vf
from verifiers.v1.runtimes import provision_runtime
from verifiers.v1.tasksets.harbor.env import HarborEnv, HarborEnvConfig
from verifiers.v1.tasksets.harbor.taskset import HarborConfig, HarborTask, parse_task
from verifiers.v1.trace import AgentInfo, TraceTask
from verifiers.v1.utils.compile import resolve_runtime_config

DATASET = Path(__file__).resolve().parents[2] / "datasets/openai-math"
sys.path.insert(0, str(DATASET / "generator"))
from openai_math_harbor import attacks  # noqa: E402

LOGS = ("grading.json", "comparator.log")
# Attacks written against one challenge's definitions; the rest use --attack-task.
ATTACK_TASKS = {"redefine-definition": "euclidean-five-color", "tamper-structure": "elementary-positivity"}
TIMEOUT_SEC = 8 * 3600


def attack_process_visibility(t: Path) -> str:
    # Lean code run at build time lists the processes it can see. Without Landlock, only the build
    # sandbox's PID namespace keeps Comparator and the grader's helpers out of reach (ptrace, signals).
    probe = """
#eval show IO Unit from do
  let mut seen := #[]
  for entry in (← System.FilePath.readDir "/proc") do
    if entry.fileName.all Char.isDigit then
      let cmd ← try IO.FS.readFile (entry.path / "cmdline") catch _ => pure "?"
      seen := seen.push s!"{entry.fileName}:{cmd.replace "\\x00" " "}"
  IO.println s!"PROBE procs: {seen}"
"""
    lean = attacks._challenge(t).replace("import Mathlib\n", "import Mathlib\n" + probe, 1)
    return attacks._write("/workspace/Submission.lean", lean)


attacks.ATTACKS["process-visibility"] = (attack_process_visibility, "Lean code run at build time lists visible processes")


def fingerprint(task: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(task.rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(task)).encode() + b"\0")
            digest.update(path.read_bytes())
    return digest.hexdigest()


def check_control(control: str, reward: float, folder: Path) -> tuple[bool, str]:
    reason = json.loads((folder / "grading.json").read_text())["reason"]
    if control == "gold":
        return reward == 1 and reason.startswith("accepted"), reason
    if control == "empty":
        return reward == 0 and "no submission" in reason, reason
    if reward != 0 or not reason.startswith("rejected"):
        return False, reason
    if control == "attack:process-visibility":
        procs = [line for line in (folder / "comparator.log").read_text().splitlines() if "PROBE procs:" in line]
        return bool(procs) and all("comparator" not in line and "grade.py" not in line for line in procs), reason
    return True, reason


async def validate(path: Path, index: int, control: str, output: Path, image_disk_gb: float) -> dict:
    folder = output / path.name / control.replace(":", "-")
    fingerprint_value = fingerprint(path)
    previous = folder / "result.json"
    if previous.exists():
        old = json.loads(previous.read_text())
        if old.get("passed") and old.get("task_sha256") == fingerprint_value:
            return old
    if folder.exists():
        # Retain every failed or stale attempt, including its logs.
        folder.rename(folder.with_name(f"{folder.name}-attempt-{time.time_ns()}"))
    folder.mkdir(parents=True)
    started = time.monotonic()
    record = {"task": path.name, "control": control, "task_sha256": fingerprint_value, "passed": False}

    class QCTask(HarborTask):
        async def run_verifier(self, runtime, trace):
            record["verifier"] = runtime.info.model_dump(mode="json")
            try:
                return await super().run_verifier(runtime, trace)
            finally:
                for name in LOGS:
                    try:
                        (folder / name).write_bytes(await runtime.read(f"/logs/verifier/{name}", max_bytes=32 << 20))
                    except Exception as exc:  # noqa: BLE001 - retain other logs after one read failure
                        (folder / f"{name}.read-error").write_text(str(exc))

    with tempfile.TemporaryDirectory() as scratch:
        task_dir = path
        if control.startswith("attack:"):
            task_dir = attacks.make_probe(path, Path(scratch), control.removeprefix("attack:"))
        try:
            data = parse_task(task_dir, index, HarborConfig(ignore_timeouts=False))
            resources = data.resources.model_copy(update={"disk": data.resources.disk + image_disk_gb})
            task = QCTask(data.model_copy(update={"resources": resources}))
            env = HarborEnv(
                HarborEnvConfig(
                    taskset={"id": "harbor"},
                    agent=vf.AgentConfig(runtime=vf.PrimeConfig(labels=["openai-math-qc"])),
                    verifier={"retries": 0},
                )
            )
            trace = vf.Trace(
                task=TraceTask(type="QCTask", data=task.data),
                agent=AgentInfo(config=env.config.agent),
                ok=True,
                is_completed=True,
            )
            async with asyncio.timeout(TIMEOUT_SEC):
                if control != "empty":
                    async with provision_runtime(resolve_runtime_config(env.config.agent.runtime, task)) as solver:
                        record["solver"] = solver.info.model_dump(mode="json")
                        await solver.prepare_setup()
                        trace.agent.runtime = solver.info
                        await task.setup(solver)
                        for file in sorted((task_dir / "solution").iterdir()):
                            await solver.write(f"/solution/{file.name}", file.read_bytes())
                        result = await solver.run(["bash", "/solution/solve.sh"], {})
                        if result.exit_code:
                            raise RuntimeError(f"solve.sh failed: {(result.stderr or result.stdout)[-2000:]}")
                        await task.finalize(trace, solver)
                episode = vf.Episode(task=trace.task, traces=[trace])
                await env.finalize(task, episode)
            record["reward"] = episode.traces[0].rewards["reward"].score
            record["passed"], record["reason"] = check_control(control, record["reward"], folder)
            record["status"] = "passed" if record["passed"] else "control_failed"
        except Exception as exc:  # noqa: BLE001 - report each task failure without abandoning the batch
            record.update(status="execution_error", error=f"{type(exc).__name__}: {exc}")
            (folder / "exception.txt").write_text(traceback.format_exc())
    record["seconds"] = round(time.monotonic() - started, 2)
    (folder / "result.json").write_text(json.dumps(record, indent=2))
    print(json.dumps({key: record.get(key) for key in ("task", "control", "status", "reward", "seconds")}), flush=True)
    return record


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dataset", type=Path, default=DATASET / "tasks")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--task", action="append", default=[], help="Exact task directory name; repeat to select tasks")
    parser.add_argument("--control", choices=("gold", "empty", "attacks"), action="append", default=[])
    parser.add_argument("--attack-task", default="truffet-counterexample", help="Task the generic attack probes use")
    parser.add_argument("--image-disk-gb", type=float, default=10.0)
    parser.add_argument("--concurrency", type=int, default=4)
    args = parser.parse_args()
    if args.concurrency < 1:
        parser.error("--concurrency must be positive")
    tasks = sorted(path.parent for path in args.dataset.glob("*/task.toml"))
    if args.task:
        unknown = set(args.task) - {path.name for path in tasks}
        if unknown:
            parser.error(f"unknown tasks: {sorted(unknown)}")
        tasks = [path for path in tasks if path.name in args.task]
    if not tasks:
        parser.error("no tasks found")
    # Validate every selected TOML before any provisioning or charges.
    for index, path in enumerate(tasks):
        parse_task(path, index, HarborConfig(ignore_timeouts=False))
    jobs = []
    for control in args.control or ["gold", "empty"]:
        if control == "attacks":
            jobs += [
                (args.dataset / ATTACK_TASKS.get(name, args.attack_task), 0, f"attack:{name}") for name in attacks.ATTACKS
            ]
        else:
            jobs += [(path, index, control) for index, path in enumerate(tasks)]
    args.output.mkdir(parents=True, exist_ok=True)
    semaphore = asyncio.Semaphore(args.concurrency)

    async def run(path, index, control):
        async with semaphore:
            return await validate(path, index, control, args.output, args.image_disk_gb)

    results = await asyncio.gather(*(run(*job) for job in jobs))
    report = {"expected": len(jobs), "passed": sum(result["passed"] for result in results), "results": results}
    (args.output / "summary.json").write_text(json.dumps(report, indent=2))
    raise SystemExit(0 if all(result["passed"] for result in results) else 1)


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING)
    asyncio.run(main())
