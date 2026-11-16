Ternaries don't work properly when used within an IndexedGetExpression's index
Using brighterscript@0.68.0, this code:

```
sub main(args as dynamic)
    someObj = {}
    overrides[someObj["abc"] = true ? someObj["abc"] : "abc"] = "ha"
end sub
```

Results in a compile error:

```
[07:20:43:013 PM] Transpiling
[07:20:43:023 PM] Error when calling plugin BscPlugin.beforeFileTranspile: RangeError: Maximum call stack size exceeded
    at walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/astUtils/visitors.ts:30:21)
    at IndexedSetStatement.walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/parser/Statement.ts:1349:17)
    at walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/astUtils/visitors.ts:84:13)
    at walkArray (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/astUtils/visitors.ts:110:29)
    at Block.walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/parser/Statement.ts:233:22)
    at walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/astUtils/visitors.ts:84:13)
    at IfStatement.walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/parser/Statement.ts:578:17)
    at BrsFilePreTranspileProcessor.processTernaryExpression (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/bscPlugin/transpile/BrsFilePreTranspileProcessor.ts:176:25)
    at Object.TernaryExpression (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/bscPlugin/transpile/BrsFilePreTranspileProcessor.ts:43:22)
    at /Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/astUtils/visitors.ts:215:51
    at walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/astUtils/visitors.ts:51:23)
    at IndexedSetStatement.walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/parser/Statement.ts:1350:17)
    at walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/astUtils/visitors.ts:84:13)
    at walkArray (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/astUtils/visitors.ts:110:29)
    at Block.walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/parser/Statement.ts:233:22)
    at walk (/Users/lse16/dev/brighterscript-test-bench/node_modules/brighterscript/src/astUtils/visitors.ts:84:13)
[07:20:43:077 PM] Transpiling finished. (63.561ms)
```

And a broken file:

![Image](https://github.com/user-attachments/assets/acd65867-342f-41b1-ab3d-778e8308a6aa)
![Image](https://github.com/user-attachments/assets/d72552f2-4243-441f-a3f0-71356f9bb8a3)
