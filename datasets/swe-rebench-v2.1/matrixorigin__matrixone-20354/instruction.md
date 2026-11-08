[Bug]: data race occurred during bvt test
### Is there an existing issue for the same bug?

- [X] I have checked the existing issues.

### Branch Name

2.0-dev

### Commit ID

0b8641a

### Other Environment Information

```Markdown
- Hardware parameters:
- OS type:
- Others:
```


### Actual Behavior


https://github.com/matrixorigin/matrixone/actions/runs/11968300034/job/33367831087

```
==================
WARNING: DATA RACE
Read at 0x00c0333492f0 by goroutine 90348:
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.fulltextIndexTokenizePrepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/fulltext_tokenize.go:83 +0x448
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.(*TableFunction).Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/table_function.go:151 +0x2289
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.(*TableFunction).ApplyPrepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/table_function.go:172 +0x48
  github.com/matrixorigin/matrixone/pkg/sql/colexec/apply.(*Apply).Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/apply/apply.go:54 +0x315
  github.com/matrixorigin/matrixone/pkg/vm.Prepare.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/vm.go:37 +0x5a
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:570 +0x237
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.HandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:574 +0x87
  github.com/matrixorigin/matrixone/pkg/vm.Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/vm.go:36 +0xfe
  github.com/matrixorigin/matrixone/pkg/vm/pipeline.(*Pipeline).Run()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/pipeline/pipeline.go:65 +0x244
  github.com/matrixorigin/matrixone/pkg/vm/pipeline.(*Pipeline).RunWithReader()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/pipeline/pipeline.go:59 +0x2d1
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).Run()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:197 +0xfe5
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).MergeRun.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:292 +0xc4
  github.com/panjf2000/ants/v2.(*goWorker).run.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:67 +0x18f

Previous write at 0x00c0333492f0 by goroutine 90705:
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.fulltextIndexTokenizePrepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/fulltext_tokenize.go:83 +0x4f4
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.(*TableFunction).Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/table_function.go:151 +0x2289
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.(*TableFunction).ApplyPrepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/table_function.go:172 +0x48
  github.com/matrixorigin/matrixone/pkg/sql/colexec/apply.(*Apply).Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/apply/apply.go:54 +0x315
  github.com/matrixorigin/matrixone/pkg/vm.Prepare.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/vm.go:37 +0x5a
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:570 +0x237
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.HandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:574 +0x87
  github.com/matrixorigin/matrixone/pkg/vm.Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/vm.go:36 +0xfe
  github.com/matrixorigin/matrixone/pkg/vm/pipeline.(*Pipeline).Run()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/pipeline/pipeline.go:65 +0x244
  github.com/matrixorigin/matrixone/pkg/vm/pipeline.(*Pipeline).RunWithReader()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/pipeline/pipeline.go:59 +0x2d1
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).Run()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:197 +0xfe5
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).MergeRun.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:292 +0xc4
  github.com/panjf2000/ants/v2.(*goWorker).run.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:67 +0x18f

Goroutine 90348 (running) created at:
  github.com/panjf2000/ants/v2.(*goWorker).run()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:48 +0xe9
  github.com/panjf2000/ants/v2.(*Pool).retrieveWorker.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:337 +0xef
  github.com/panjf2000/ants/v2.(*Pool).retrieveWorker()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:348 +0x2a6
  github.com/panjf2000/ants/v2.(*Pool).Submit()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:222 +0xa6
  github.com/panjf2000/ants/v2.Submit()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/ants.go:103 +0x4e
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).MergeRun()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:288 +0x6dc
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Compile).run()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/compile.go:331 +0xb46
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Compile).runOnce.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/compile.go:497 +0x190
  github.com/panjf2000/ants/v2.(*goWorker).run.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:67 +0x18f

Goroutine 90705 (running) created at:
  github.com/panjf2000/ants/v2.(*goWorker).run()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:48 +0xe9
  github.com/panjf2000/ants/v2.(*Pool).retrieveWorker.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:337 +0xef
  github.com/panjf2000/ants/v2.(*Pool).retrieveWorker()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:348 +0x2a6
  github.com/panjf2000/ants/v2.(*Pool).Submit()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:222 +0xa6
  github.com/panjf2000/ants/v2.Submit()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/ants.go:103 +0x4e
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).MergeRun()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:288 +0x6dc
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Compile).run()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/compile.go:331 +0xb46
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Compile).runOnce.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/compile.go:497 +0x190
  github.com/panjf2000/ants/v2.(*goWorker).run.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:67 +0x18f
==================
==================
WARNING: DATA RACE
Write at 0x00c0333492f0 by goroutine 90348:
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.fulltextIndexTokenizePrepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/fulltext_tokenize.go:83 +0x4f4
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.(*TableFunction).Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/table_function.go:151 +0x2289
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.(*TableFunction).ApplyPrepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/table_function.go:172 +0x48
  github.com/matrixorigin/matrixone/pkg/sql/colexec/apply.(*Apply).Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/apply/apply.go:54 +0x315
  github.com/matrixorigin/matrixone/pkg/vm.Prepare.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/vm.go:37 +0x5a
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:570 +0x237
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.HandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:574 +0x87
  github.com/matrixorigin/matrixone/pkg/vm.Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/vm.go:36 +0xfe
  github.com/matrixorigin/matrixone/pkg/vm/pipeline.(*Pipeline).Run()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/pipeline/pipeline.go:65 +0x244
  github.com/matrixorigin/matrixone/pkg/vm/pipeline.(*Pipeline).RunWithReader()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/pipeline/pipeline.go:59 +0x2d1
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).Run()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:197 +0xfe5
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).MergeRun.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:292 +0xc4
  github.com/panjf2000/ants/v2.(*goWorker).run.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:67 +0x18f

Previous write at 0x00c0333492f0 by goroutine 90346:
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.fulltextIndexTokenizePrepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/fulltext_tokenize.go:83 +0x4f4
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.(*TableFunction).Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/table_function.go:151 +0x2289
  github.com/matrixorigin/matrixone/pkg/sql/colexec/table_function.(*TableFunction).ApplyPrepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/table_function/table_function.go:172 +0x48
  github.com/matrixorigin/matrixone/pkg/sql/colexec/apply.(*Apply).Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/colexec/apply/apply.go:54 +0x315
  github.com/matrixorigin/matrixone/pkg/vm.Prepare.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/vm.go:37 +0x5a
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:570 +0x237
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.doHandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:566 +0x17e
  github.com/matrixorigin/matrixone/pkg/vm.HandleAllOp()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/types.go:574 +0x87
  github.com/matrixorigin/matrixone/pkg/vm.Prepare()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/vm.go:36 +0xfe
  github.com/matrixorigin/matrixone/pkg/vm/pipeline.(*Pipeline).Run()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/pipeline/pipeline.go:65 +0x244
  github.com/matrixorigin/matrixone/pkg/vm/pipeline.(*Pipeline).RunWithReader()
      /home/runner/_work/matrixone/matrixone/head/pkg/vm/pipeline/pipeline.go:59 +0x2d1
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).Run()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:197 +0xfe5
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).MergeRun.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:292 +0xc4
  github.com/panjf2000/ants/v2.(*goWorker).run.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:67 +0x18f

Goroutine 90348 (running) created at:
  github.com/panjf2000/ants/v2.(*goWorker).run()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:48 +0xe9
  github.com/panjf2000/ants/v2.(*Pool).retrieveWorker.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:337 +0xef
  github.com/panjf2000/ants/v2.(*Pool).retrieveWorker()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:348 +0x2a6
  github.com/panjf2000/ants/v2.(*Pool).Submit()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:222 +0xa6
  github.com/panjf2000/ants/v2.Submit()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/ants.go:103 +0x4e
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Scope).MergeRun()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/scope.go:288 +0x6dc
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Compile).run()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/compile.go:331 +0xb46
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Compile).runOnce.func1()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/compile.go:497 +0x190
  github.com/panjf2000/ants/v2.(*goWorker).run.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:67 +0x18f

Goroutine 90346 (running) created at:
  github.com/panjf2000/ants/v2.(*goWorker).run()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/worker.go:48 +0xe9
  github.com/panjf2000/ants/v2.(*Pool).retrieveWorker.func1()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:337 +0xef
  github.com/panjf2000/ants/v2.(*Pool).retrieveWorker()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:348 +0x2a6
  github.com/panjf2000/ants/v2.(*Pool).Submit()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/pool.go:222 +0xa6
  github.com/panjf2000/ants/v2.Submit()
      /home/runner/go/pkg/mod/github.com/panjf2000/ants/v2@v2.7.4/ants.go:103 +0x4e
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Compile).runOnce()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/compile.go:487 +0x43c
  github.com/matrixorigin/matrixone/pkg/sql/compile.(*Compile).Run()
      /home/runner/_work/matrixone/matrixone/head/pkg/sql/compile/compile2.go:245 +0x160f
  github.com/matrixorigin/matrixone/pkg/frontend.executeStatusStmt()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/status_stmt.go:141 +0x188e
  github.com/matrixorigin/matrixone/pkg/frontend.executeStmt()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/mysql_cmd_executor.go:2799 +0x2ec8
  github.com/matrixorigin/matrixone/pkg/frontend.dispatchStmt()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/mysql_cmd_executor.go:2647 +0x6f6
  github.com/matrixorigin/matrixone/pkg/frontend.executeStmtWithIncrStmt()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/mysql_cmd_executor.go:2616 +0x9b5
  github.com/matrixorigin/matrixone/pkg/frontend.executeStmtWithWorkspace()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/mysql_cmd_executor.go:2560 +0xeee
  github.com/matrixorigin/matrixone/pkg/frontend.executeStmtWithTxn()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/mysql_cmd_executor.go:2451 +0x384
  github.com/matrixorigin/matrixone/pkg/frontend.executeStmtWithResponse()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/mysql_cmd_executor.go:2414 +0xa46
  github.com/matrixorigin/matrixone/pkg/frontend.doComQuery()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/mysql_cmd_executor.go:3048 +0x4b04
  github.com/matrixorigin/matrixone/pkg/frontend.ExecRequest()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/mysql_cmd_executor.go:3125 +0x12e4
  github.com/matrixorigin/matrixone/pkg/frontend.(*Routine).handleRequest()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/routine.go:298 +0x10f1
  github.com/matrixorigin/matrixone/pkg/frontend.(*RoutineManager).Handler()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/routine_manager.go:385 +0x875
  github.com/matrixorigin/matrixone/pkg/frontend.(*MOServer).handleRequest()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/server.go:516 +0x484
  github.com/matrixorigin/matrixone/pkg/frontend.(*MOServer).handleMessage()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/server.go:484 +0x10a
  github.com/matrixorigin/matrixone/pkg/frontend.(*MOServer).handleLoop()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/server.go:212 +0x91
  github.com/matrixorigin/matrixone/pkg/frontend.(*MOServer).handleConn()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/server.go:208 +0x8fa
  github.com/matrixorigin/matrixone/pkg/frontend.(*MOServer).startAccept.gowrap2()
      /home/runner/_work/matrixone/matrixone/head/pkg/frontend/server.go:177 +0x9e
==================
```



### Expected Behavior

_No response_

### Steps to Reproduce

```Markdown
run ut with race enabled
```


### Additional information

_No response_

### Additional contract requirements

- The full-text table function must be safe to prepare concurrently: preparing the
  operator from several goroutines at the same time must not produce a data race.


- `fulltext_index_tokenize` must return four rows for the plain-text input `this is a text`. For the JSON input `{"a":"matrixone"}`, it must return one row with each of the `json` and `json_value` parser modes.
