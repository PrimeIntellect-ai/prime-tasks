NamespaceResolver doesn't cache anything resulting in imports being fetched on every run
**Describe the bug**
The first loc that gets executed on the NamespaceResolver is:
```php
[HIDDEN]
```
without caching or any other optimisation. This means the umber of times an object is mapped is equal the the number
of times the imports are loaded. Even when mapping the same object. The `UseStatementHelper::getImports` is an expensive call as it loads the object class source code into an AST to fetch the used imports.

**To Reproduce**
I've created a vanilla script
```php
<?php
# ./tests/Benchmark/vanilla.php

declare(strict_types=1);

use JsonMapper\JsonMapperFactory;
use JsonMapper\Tests\Benchmark\Joke;

chdir(__DIR__ . '/../../');
require_once 'vendor/autoload.php';

$mapper = (new JsonMapperFactory())->bestFit();

for ($x = 1; $x < 1000; $x++) {
    $joke = new Joke();
    $json = '{"id":131,"type":"general","setup":"How do you organize a space party?","punchline":"You planet."}';
    $mapper->mapObjectFromString($json, $joke);
}
```
which I've executed with the Xdebug profile enabled. See the screenshot attached. It shows that getting the imports took 80%time.
<img width="1570" alt="Screenshot 2021-04-15 at 21 01 20" src="https://user-images.githubusercontent.com/618940/114924040-d0e02700-9e2d-11eb-929e-5d339eb57416.png">

**Expected behavior**
Since the source code is not expected to change at runtime we should cache the results similar how the other middleware does this.

**Stacktrace**

**Environment (please complete the following information):**
 - PHP: 8.0
 - XDebug: 3.0

**Additional context**
This research was triggered by the question from @TeroBlaZe in #80
