feat: support check constraint
```go
 --- FAIL: TestCreateTable/Identifier_lengths (0.05s)
        --- FAIL: TestCreateTable/Identifier_lengths/create_table_b_(a_int_primary_key,_constraint_abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl_check_(a_>_0)) (0.00s)
            /Users/shannon/code/myduckserver/evaluation.go:351:
                	Error Trace:	/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/enginetest/evaluation.go:351
                	Error:      	Received unexpected error:
                	            	the table does not support check constraint operations: b

                	            	github.com/dolthub/go-mysql-server/sql/plan.(*CreateTable).CreateChecks
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/plan/ddl.go:422
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).buildCreateTable
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/ddl.go:1060
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).buildNodeExecNoAnalyze
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/node_builder.gen.go:96
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).buildNodeExec
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/node_builder.gen.go:36
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).Build
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/builder.go:39
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).buildTransactionCommittingNode
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/transaction.go:305
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).buildNodeExecNoAnalyze
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/node_builder.gen.go:58
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).buildNodeExec
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/node_builder.gen.go:36
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).Build
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/builder.go:39
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).buildQueryProcess
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/other.go:371
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).buildNodeExecNoAnalyze
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/node_builder.gen.go:68
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).buildNodeExec
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/node_builder.gen.go:36
                	            	github.com/dolthub/go-mysql-server/sql/rowexec.(*BaseBuilder).Build
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/sql/rowexec/builder.go:39
                	            	github.com/apecloud/myduckserver.(*DuckBuilder).Build
                	            		/Users/shannon/code/myduckserver/executor.go:107
                	            	github.com/dolthub/go-mysql-server.(*Engine).QueryWithBindings
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/engine.go:415
                	            	github.com/dolthub/go-mysql-server/enginetest.TestQueryWithContext
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/enginetest/evaluation.go:350
                	            	github.com/dolthub/go-mysql-server/enginetest.TestScriptWithEngine.func1.1
                	            		/Users/shannon/go/pkg/mod/github.com/dolthub/go-mysql-server@v0.18.2-0.20240815142344-761713e36043/enginetest/evaluation.go:142
                	            	testing.tRunner
                	            		/opt/homebrew/Cellar/go/1.23.0/libexec/src/testing/testing.go:1690
                	            	runtime.goexit
                	            		/opt/homebrew/Cellar/go/1.23.0/libexec/src/runtime/asm_arm64.s:1223
                	Test:       	TestCreateTable/Identifier_lengths/create_table_b_(a_int_primary_key,_constraint_abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl_check_(a_>_0))
                	Messages:   	Unexpected error for query create table b (a int primary key, constraint abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl check (a > 0)): the table does not support check constraint operations: b
```

### Additional contract requirements

CHECK constraints must be enforced when rows are inserted: an insert that satisfies the constraint succeeds, and an insert that violates it is rejected. A table created with `CREATE TABLE ... LIKE` must retain its CHECK constraints and enforce them on subsequent inserts.
