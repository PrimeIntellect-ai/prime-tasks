Detecting unhandled rejections
When using promises, there are a good chance that some code will forget to handle rejections/exceptions in a promise chain. This has the result of effectively hidding any rejection/exception that occurred during the execution of a promise's callback, which is dangerous and can lead to undetected bugs.

What makes this worse is that is suffices of a single error/forget in a promise chain to hide all exceptions thrown anywhere in the chain, including errors in react-php: reactphp/http-client#31, reactphp/dns#26.

It's super easy to not handle a rejection: if a promise chain is ended by anything except `done()`, any errors in the chain will be unhandled and potentially hidden:

```
$promise->always(function() {
    doSomething();
});
```

This example is quite obvious: any exception thrown in doSomething() is caught and hidden from the user.

Other example from react/http-client:

```
$promise->then(function () {
    // ok
}, function ($err) {
    $this->emit('error', $err);
    // in the 'error' callback:
    $this->retry();
})->then(function () {
    doSomething();
});
```

This one is less obvious. In this example, any exception thrown in retry() is caught by the promise and effectively hidden from the user.

Some promise implementations are trying to detect unhandled rejections, and log them: http://bluebirdjs.com/docs/api/error-management-configuration.html

It is possible to do so in react/promise too. [HIDDEN]

Here is a PoC adding tracing functionality to promises: https://github.com/arnaud-lb/promise/commit/90e6e350c0464961c032e196826bc509dfe1cc82

And here is a PoC tracer that detects unhandled rejections: https://gist.github.com/arnaud-lb/a2a5a5480bbd80013f756ff968282936

This can be used like this:

```
<?php

$tracer = new UnhandledRejectionTracer(function ($info) {
    var_dump("unhandled promise", $info);
});
RejectedPromise::setTracer($tracer);
FulfilledPromise::setTracer($tracer);

register_shutdown_function(function () use ($tracer) {
    // handle non-destructed promises
    foreach ($tracer->getRemainingPromises() as $info) {
        var_dump("unhandled promise", $info);
    }
});
```

This immediately discovered a few bugs in my code. I'm using this since a few months already, and this prevents the introduction of new bugs.

### Additional contract requirements

- A rejected promise discarded without a rejection handler must be reported as an unhandled rejection. A rejected promise with a rejection handler must not itself be reported as unhandled.
- When reporting an unhandled rejection, emit the diagnostic to the PHP error log in this format: `Unhandled promise rejection with <class>: <message> in <file>:<line>`, followed by a newline, `Stack trace:`, a newline, and the throwable's stack trace in PHP's `#N ...` format.
- Calling `cancel()` on a promise marks it as handled: a promise that is cancelled does not emit the unhandled rejection diagnostic, regardless of whether the rejection occurs before or after the cancellation.
