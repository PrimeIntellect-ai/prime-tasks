Attributes with unrecognized annotations will fail
Hey there,

I have a generic benchmark class so that I can test multiple implementations of the same interface at once.
This looks somehow like:

```php
/**
 * @template TOptions of AdapterOptions
 */
#[BeforeMethods('setUp')]
#[AfterMethods('tearDown')]
abstract class AbstractStorageAdapterBenchmark
{}
```

That class is then extended by the concrete implementation benchmark:

```php
/**
 * @template-extends AbstractStorageAdapterBenchmark<RedisClusterOptions>
 */
#[Revs(100)]
#[Iterations(10)]
#[Warmup(1)]
class RedisClusterStorageAdapterBench extends AbstractStorageAdapterBenchmark
{}
```

It seems that phpbench does ignore all attributes once a phpdoc on class level is provided.
I assume that this is a bug?

Ref: https://github.com/laminas/laminas-cache-storage-adapter-redis/actions/runs/9620252082/job/26538088931?pr=101
Ref: https://github.com/laminas/laminas-cache-storage-adapter-redis/blob/573ba3b9e1b1f18152230e5216a9c462a22fc57b/benchmark/RedisClusterStorageAdapterBench.php

```
Running ./vendor/bin/phpbench run --revs=2 --iterations=2 --report=aggregate
No entry for terminal type "unknown";
using dumb terminal settings.
PHPBench (1.2.15) running benchmarks... #standwithukraine
with configuration file: /github/workspace/phpbench.json
with PHP version 8.1.27, xdebug ❌, opcache ❌

Warning:  Could not load metadata for file "/github/workspace/benchmark/RedisClusterStorageAdapterBench.php" - is this file intended to be a benchmark? Perhaps setting the `runner.file_pattern` to `*Bench.php` will help: Unrecognized annotation @template, valid PHPBench annotations: @BeforeMethods, @BeforeClassMethods, @AfterMethods, @AfterClassMethods, @ParamProviders, @Groups, @Iterations, @Revs, @Skip, @Sleep, @OutputTimeUnit, @OutputMode, @Warmup, @Subject, @Assert, @Executor, @Timeout, @Format, @RetryThreshold
```

### Additional contract requirements

- Generic PHPDoc annotations such as `@template`, `@template-covariant`, `@template-contravariant`, `@extends`, `@implements`, and `@use` must not be treated as unrecognized PHPBench annotations or prevent benchmark metadata from loading.
- PHPBench attributes declared on a benchmark class must continue to affect its benchmark metadata when that class has generic annotations in its PHPDoc.
- The concrete benchmark’s `@template-extends` annotation must not be rejected or prevent its metadata from loading.
