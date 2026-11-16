SimpleBatcher apparent deadlock
I am using version 6.2.0.RELEASE.
I would like to ask about the Batch Execution using asynchronous commands like [wiki](https://github.com/lettuce-io/lettuce-core/wiki/Redis-Command-Interfaces).
```java
@BatchSize(50)
interface StringCommands extends Commands {
    RedisFuture<String> get(String key, CommandBatching batching);
}

StringCommands commands = …
commands.get("key1", CommandBatching.queue());
commands.get("key2", CommandBatching.flush());
```
If the above codes run with multi threads, sometimes RedisFuture.get() will block for ever, actually some commands are not send to the Redis Server.
It might caused by io.lettuce.core.dynamic.SimpleBatcher#flush(boolean), "while (flushing.compareAndSet(false, true))".

Thank you!
