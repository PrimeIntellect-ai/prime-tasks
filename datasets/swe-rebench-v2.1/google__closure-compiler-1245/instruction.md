closure compiler crashes for some es6 input
```js
var z = require('./node_1')

function fib(n){
    "use strict";
    if(n===0||n===1){
        return 1
    } else{
        return fib(n-1) + fib(n-2)
    }
}
module.exports = {
    used2 (x) {
        "use strict";
        return z.used1(3,x)
    },
    fib // works with : fib
}
```

```
java.lang.RuntimeException: INTERNAL COMPILER ERROR.
Please report this problem.

null
  Node(SCRIPT): node_2.js:4:0
var z = require('./node_1')
  Parent: NULL
        [HIDDEN]
        at com.google.javascript.jscomp.ProcessCommonJSModules$ProcessCommonJsModulesCallback.visitScript(ProcessCommonJSModules.java:299)
        at com.google.javascript.jscomp.ProcessCommonJSModules$ProcessCommonJsModulesCallback.visit(ProcessCommonJSModules.java:235)
        at com.google.javascript.jscomp.NodeTraversal.traverseBranch(NodeTraversal.java:611)
        at com.google.javascript.jscomp.NodeTraversal.traverse(NodeTraversal.java:297)
        at com.google.javascript.jscomp.NodeTraversal.traverseEs6(NodeTraversal.java:562)
        at com.google.javascript.jscomp.ProcessCommonJSModules.process(ProcessCommonJSModules.java:85)
        at com.google.javascript.jscomp.Compiler.processAMDAndCommonJSModules(Compiler.java:1493)
	at com.google.javascript.jscomp.Compiler.parseInputs(Compiler.java:1299)
        at com.google.javascript.jscomp.Compiler.parse(Compiler.java:704)
        at com.google.javascript.jscomp.Compiler.compileInternal(Compiler.java:665)
        at com.google.javascript.jscomp.Compiler.access$000(Compiler.java:89)
        at com.google.javascript.jscomp.Compiler$2.call(Compiler.java:636)
        at com.google.javascript.jscomp.Compiler$2.call(Compiler.java:633)
        at com.google.javascript.jscomp.CompilerExecutor$2.call(CompilerExecutor.java:93)
        at java.util.concurrent.FutureTask.run(FutureTask.java:266)
        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1142)
        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:617)
        at java.lang.Thread.run(Thread.java:745)
Caused by: java.lang.NullPointerException
```
