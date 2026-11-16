Using a Named Reference more than once in the same formula throws and "Edge does not exist" error
### Description

A formula that includes the same Named Reference more than once should work but it actually throws an error of "Edge does not exist".  If the ColRow naming convention is used instead it does work correctly. e.g. "= age + age" throws error while "= H1 + H1" works.

### Steps to reproduce
```
import { HyperFormula } from "hyperformula";
const options = {
    licenseKey: 'gpl-v3'
};

const data = [['10', '20', '55', '= age + age']];

const hfInstance = HyperFormula.buildFromArray(data, options);
hfInstance.addNamedExpression('age', '=Sheet1!$c$1', 0);

const answer = hfInstance.getCellValue({ col: 3, row: 0, sheet: 0 });
console.log(answer);
```

This throws the following error

```
Error: Edge does not exist
    at Graph.removeEdge (C:\dev\poc\hyper-formula-bug\node_modules\hyperformula\commonjs\DependencyGraph\Graph.js:83:13)
    at Operations.adjustNamedExpressionEdges (C:\dev\poc\hyper-formula-bug\node_modules\hyperformula\commonjs\Operations.js:876:40)
    at Operations.addNamedExpression (C:\dev\poc\hyper-formula-bug\node_modules\hyperformula\commonjs\Operations.js:364:10)
    at CrudOperations.addNamedExpression (C:\dev\poc\hyper-formula-bug\node_modules\hyperformula\commonjs\CrudOperations.js:363:21)
    at HyperFormula.addNamedExpression (C:\dev\poc\hyper-formula-bug\node_modules\hyperformula\commonjs\HyperFormula.js:3776:26)
    at file:///C:/dev/poc/hyper-formula-bug/test.js:9:12
    at ModuleJob.run (node:internal/modules/esm/module_job:193:25)
    at async Promise.all (index 0)
    at async ESMLoader.import (node:internal/modules/esm/loader:530:24)
    at async loadESM (node:internal/process/esm_loader:91:5)
```

### Your environment
<!--- [recommended]  -->

* HyperFormula version: 2.1.0
* Browser Name and version: node.js or any browser
* Operating System: Windows
