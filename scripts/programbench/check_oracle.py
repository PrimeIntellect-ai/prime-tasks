"""Check saved author-oracle logs; never use this as a candidate reward function."""

import argparse
import json
import runpy
from collections import Counter
from pathlib import Path


def check(task_dir: Path, logs_dir: Path) -> dict:
    # Reuse the pinned task's active/ignored-case and scoring rules. Only load
    # trusted task code, never anything from the candidate submission.
    evaluator = runpy.run_path(str(task_dir / "tests/programbench_evaluator.py"))
    metadata = json.loads((task_dir / "tests/programbench_task.json").read_text())
    result = json.loads((logs_dir / "programbench_eval.json").read_text())
    reward = json.loads((logs_dir / "reward.json").read_text())
    diagnostics = json.loads((logs_dir / "harbor_diagnostics.json").read_text())
    scored = evaluator["scored_results"](result, metadata)
    statuses = Counter(test["status"] for test in scored)
    missing = [
        f"{test['branch']}/{test['name']}"
        for test in scored
        if test["status"] == "not_run"
    ]
    recomputed_reward = evaluator["summarize"](result, metadata)
    recomputed_diagnostics = evaluator["diagnostics"](result, metadata)
    consistent = reward == recomputed_reward and diagnostics == recomputed_diagnostics
    passed = bool(
        scored
        and statuses["passed"] == len(scored)
        and not result["error_code"]
        and not result["test_branch_errors"]
        and consistent
    )
    return {
        "task": task_dir.name,
        "oracle_pass": passed,
        "n_expected": len(scored),
        "statuses": dict(statuses),
        "missing_cases": missing,
        "error_code": result["error_code"],
        "branch_errors": result["test_branch_errors"],
        "outputs_consistent": consistent,
        "reward": reward,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("task_dir", type=Path)
    parser.add_argument("logs_dir", type=Path)
    args = parser.parse_args()
    try:
        report = check(args.task_dir, args.logs_dir)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({"oracle_pass": False, "invalid_logs": str(exc)}, indent=2))
        raise SystemExit(1) from exc
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report["oracle_pass"] else 1)


if __name__ == "__main__":
    main()
