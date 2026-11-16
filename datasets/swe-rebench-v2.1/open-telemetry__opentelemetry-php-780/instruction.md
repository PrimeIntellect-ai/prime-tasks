`Event\Dispatcher::getInstance()` leaks scope
**Steps to reproduce**
```php
$key = Context::createKey('-');
$scope = Context::getCurrent()->with($key, 1)->activate();
Dispatcher::getInstance();
$result = $scope->detach();

assert($result === 0); // currently MISMATCH | 1
assert(Context::getCurrent()->get($key) === null); // currently 1
```

**What is the expected behavior?**
`Event\Dispatcher::getInstance()` does not create a scope.

**What is the actual behavior?**
`Event\Dispatcher::getInstance()` creates a scope that is never detached.

**Additional context**
See also https://github.com/open-telemetry/opentelemetry-php/pull/763#discussion_r923037358.

### Additional contract requirements

The accessor method has been renamed from `getInstance()` to `getRoot()`. The public
interface is `Dispatcher::getRoot()`; `getInstance()` is no longer part of the public
interface. The requirement that accessing the root event dispatcher does not create or
activate a Context scope applies to `Dispatcher::getRoot()`.
