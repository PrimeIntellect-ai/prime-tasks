import sys
import job_pb2

def main():
    base_deps = [
        (10, 20), (20, 30), (5, 15), (15, 25), (30, 40),
        (2, 4), (4, 8), (8, 16), (3, 6), (6, 12)
    ]

    deps = {u: set() for u, v in base_deps}
    for u, v in base_deps:
        if v not in deps: deps[v] = set()
        deps[v].add(u)

    executed = set()
    pending = set()
    log = []

    with open(sys.argv[1], "rb") as f:
        prog = job_pb2.Program()
        prog.ParseFromString(f.read())

    for inst in prog.instructions:
        if inst.op == job_pb2.Instruction.ADD_JOB:
            pending.add(inst.u)
        elif inst.op == job_pb2.Instruction.ADD_DEP:
            if inst.v not in deps: deps[inst.v] = set()
            deps[inst.v].add(inst.u)
        elif inst.op == job_pb2.Instruction.EXECUTE:
            ready = []
            for job in pending:
                job_deps = deps.get(job, set())
                if job_deps.issubset(executed):
                    ready.append(job)
            ready.sort()
            for job in ready:
                pending.remove(job)
                executed.add(job)
                log.append(job)

    print(",".join(map(str, log)))

if __name__ == "__main__":
    main()
