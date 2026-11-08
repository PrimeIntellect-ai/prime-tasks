Add support enum dynamic constant
PHP: 8.3.1
When i use dynamic constants for enum.
For example:
```php
<?php declare(strict_types = 1);

enum Foo
{
	case Bar;
}

$variable = 'Bar';
$const = Foo::{$variable};
```
https://phpstan.org/r/fc74146a-7438-4cd8-ae4c-56c8db97dad5

<details>
<summary>Screenshot</summary>

![Screenshot 2024-01-21 at 4 04 15 PM](https://github.com/spaze/phpstan-disallowed-calls/assets/34651075/d73de7d4-73a8-4082-8362-8c0a14c04878)
</details>


I catch error
```
Uncaught PHPStan\ShouldNotHappenException: $node->name should be PhpParser\Node\Identifier but is PhpParser\Node\Expr\PropertyFetch in /api/vendor/spaze/phpstan-disallowed-calls/src/Usages/ClassConstantUsages.php: 84
#0 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Analyser/FileAnalyser.php(107): Spaze\PHPStan\Rules\Disallowed\Usages\ClassConstantUsages->processNode(Object(PhpParser\Node\Expr\ClassConstFetch), Object(PHPStan\Analyser\MutatingScope))
#1 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Node/ClassStatementsGatherer.php(108): PHPStan\Analyser\FileAnalyser->PHPStan\Analyser\{closure}(Object(PhpParser\Node\Expr\ClassConstFetch), Object(PHPStan\Analyser\MutatingScope))
#2 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Analyser/NodeScopeResolver.php(567): PHPStan\Node\ClassStatementsGatherer-> __ invoke(Object(PhpParser\Node\Expr\ClassConstFetch), Object(PHPStan\Analyser\MutatingScope)
#3 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Analyser/NodeScopeResolver.php(2653): PHPStan\Analyser\NodeScopeResolver: : PHPStan\Analyser\{closure}(Object(PhpParser\Node\Expr\ClassConstFetch), Object(PHPStan\Analyser\MutatingScope))
#4 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Analyser/NodeScopeResolver.php(1592): PHPStan\Analyser\NodeScopeResolver->callNodeCallbackWithExpression(Object(Closure), Object(PhpParser\Node\Expr\ClassConstFetch), Object(PHPStan\Analyser\MutatingScope), ObjectPHPStan\Analyser\ExpressionContext))
#5 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Analyser/NodeScopeResolver.php(605): PHPStan\Analyser\NodeScopeResolver->processExprNode(Object(PhpParser\Node\Stmt\Return_), Object(PhpParser\Node\Expr\ClassConstFetch), Object(PHPStan\Analyser\MutatingScope), Object(Closure), Object(PHPStan\Analyser\ExpressionContext))
#6 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Analyser/NodeScopeResolver.php(401): PHPStan\Analyser\NodeScopeResolver->processStmtNode(Object(PhpParser\Node\Stmt\Return_), Object(PHPStan\Analyser\MutatingScope), Object(Closure), Object(PHPStan\Analyser\StatementContext))
#7 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Analyser/NodeScopeResolver.php(566): PHPStan\Analyser\NodeScopeResolver->processStmtNodes(Object(PhpParser\Node\Stmt\ClassMethod), Array, Object(PHPStan\Analyser\MutatingScope), Object(Closure), Object(PHPStan\Analyser\StatementContext))
#8 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Analyser/NodeScopeResolver.php(401): PHPStan\Analyser\NodeScopeResolver->processStmtNode(Object(PhpParser\Node\Stmt\ClassMethod), Object(PHPStan\Analyser\MutatingScope), Object(PHPStan\Node\ClassStatementsGatherer), Object(PHPStan\Analyser\StatementContext))
#9 phar:///api/vendor/phpstan/phpstan/phpstan.phar/src/Analyser/NodeScopeResolver.php(668): PHPStan\Analyser\NodeScopeResolver->processStmtNodes(Object(PhpParser\Node\Stmt\Class_), Array, Object(PHPStan\Analyser\MutatingScope), Object(PHPStan\Node\ClassStatementsGatherer), Object(PHPStan\Analyser\StatementContext))
```

<details>
<summary>Screenshot</summary>

![Screenshot 2024-01-21 at 4 02 54 PM](https://github.com/spaze/phpstan-disallowed-calls/assets/34651075/6211a05c-870c-4cb5-83fc-7f4ae7dec17b)
</details>

### Additional contract requirements

Dynamic class constant fetch (`Foo::{$variable}`, PHP 8.3) must be supported for both enums and ordinary classes. When the type of the variable used as the constant name is known to be a constant string (or a union of constant strings), the rule must report every resolved constant that is disallowed, using the same message format as a static constant access, for example `Using Waldo\Quux\Blade::RUNNER is forbidden, not a replicant.` for an ordinary class and `Using Waldo\Quux\BladeEnum::RUNNER is forbidden, enum replicant.` for an enum. Dynamic accesses that resolve only to allowed constants, or whose constant name cannot be resolved to a known constant string, must not be reported.
