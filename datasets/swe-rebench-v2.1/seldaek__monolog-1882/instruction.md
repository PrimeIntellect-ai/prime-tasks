ErrorException: Caught ErrorException (HTTP/1.0 500 Internal Server Error): fwrite(): write of X bytes failed with errno=32 Broken pipe
Monolog version 2

Got these lot of errors when sudden burst traffic hit the service. Even though the request end up success with HTTP 200, unfortunately this make additional at least ~2s latency for every processed requests thus slowing down the service.

Stacktrace:
```
ErrorException: Caught ErrorException (HTTP/1.0 500 Internal Server Error): fwrite(): write of 111 bytes failed with errno=32 Broken pipe in /var/www/app/vendor/monolog/monolog/src/Monolog/Handler/StreamHandler.php:178
#0 [internal function]: Laravel\Lumen\Application->Laravel\Lumen\Concerns\{closure}()
#1 /var/www/app/vendor/monolog/monolog/src/Monolog/Handler/StreamHandler.php(178): fwrite()
#2 /var/www/app/vendor/monolog/monolog/src/Monolog/Handler/StreamHandler.php(162): Monolog\Handler\StreamHandler->streamWrite()
#3 /var/www/app/vendor/monolog/monolog/src/Monolog/Handler/AbstractProcessingHandler.php(48): Monolog\Handler\StreamHandler->write()
#4 /var/www/app/vendor/monolog/monolog/src/Monolog/Logger.php(327): Monolog\Handler\AbstractProcessingHandler->handle()
#5 /var/www/app/vendor/monolog/monolog/src/Monolog/Logger.php(565): Monolog\Logger->addRecord()
#6 /var/www/app/vendor/illuminate/log/Logger.php(174): Monolog\Logger->error()
#7 /var/www/app/vendor/illuminate/log/Logger.php(87): Illuminate\Log\Logger->writeLog()
#8 /var/www/app/vendor/illuminate/log/LogManager.php(543): Illuminate\Log\Logger->error()
#9 /var/www/app/vendor/laravel/lumen-framework/src/Exceptions/Handler.php(56): Illuminate\Log\LogManager->error()
#10 /var/www/app/app/Exceptions/Handler.php(51): Laravel\Lumen\Exceptions\Handler->report()
#11 /var/www/app/vendor/laravel/lumen-framework/src/Concerns/RegistersExceptionHandlers.php(104): App\Exceptions\Handler->report()
#12 /var/www/app/vendor/laravel/lumen-framework/src/Concerns/RoutesRequests.php(174): Laravel\Lumen\Application->sendExceptionToHandler()
#13 /var/www/app/vendor/laravel/lumen-framework/src/Concerns/RoutesRequests.php(109): Laravel\Lumen\Application->dispatch()
#14 /var/www/app/public/index.php(28): Laravel\Lumen\Application->run()
#15 {main}
```

I use stdout and stderr for channels. It's then collected by filebeat then sent to ES. This is standard EFK stack in kubernetes cluster.

I thought that the disk is full, but I was wrong. The disk is still far from full. Then I suspect two things:
- the log may be too big to handle (2.2 million logs per day) so doing some filters become necessary, or
- there's a misconfiguration on my config
```
        'stderr' => [
            'driver' => 'monolog',
            'handler' => StreamHandler::class,
            'with' => [
                'stream' => 'php://stderr',
            ],
        ],

        'stdout' => [
            'driver' => 'monolog',
            'handler' => StreamHandler::class,
            'formatter' => Monolog\Formatter\LineFormatter::class,
            'formatter_with' => [
                'format' => "[%datetime%] ".env('APP_NAME', 'app-name').".%level_name%: %message%\n",
                'dateFormat' => 'Y-m-d H:i:s',
            ],
            'with' => [
                'stream' => 'php://stdout',
            ],
        ],
```
I was wondering why it says HTTP 500 internal server error? It's from php error message right? 🤔

I just think this kind of monolog error doesn't affect the application.

Wondering if anyone face the same issue.
Any help is appreciated.


Issue with Logging to stdout in Laravel 10.21 using Monolog v3 EXCEPTION#Cannot log request: fwrite(): Write of 378 bytes failed with errno=32 Broken pipe
Monolog version 3

Hello,

I'm currently working with Laravel 10.21 and have encountered an issue when attempting to write logs to stdout using Monolog version 3. My configuration is as follows:

```php
'stdout' => [
    'driver' => 'monolog',
    'handler' => StreamHandler::class,
    'formatter' => '\Monolog\Formatter\JsonFormatter',
    'with' => [
        'stream' => 'php://stdout',
    ],
],

```

However, this setup results in an exception:


```ruby
Exception: /var/www/html/vendor/monolog/monolog/src/Monolog/Handler/StreamHandler.php::162 -> EXCEPTION#Cannot log request: fwrite(): Write of 378 bytes failed with errno=32 Broken pipe

```

I noticed a similar issue previously reported as [#1634](https://github.com/Seldaek/monolog/issues/1634), but it seems the problem persists. Any guidance or suggestions to resolve this would be greatly appreciated.

Thank you for your support.

Best regards,
The file does not close after writing
Monolog version 3

We use Laravel and queues. Queue is maintained by supervisor.

The queue writes a log.  But after deleting the log, the task in the queue no longer writes to the log. All because the file does not close after writing (fclose).

Here src/Monolog/Handler/StreamHandler.php, method write, but then it doesn't close stream.

I tested, if I added a fclose($stream) at the end of the write method, the problem disappears.

### Additional contract requirements

If a stream write fails temporarily and a subsequent write can succeed, logging the record must complete without propagating that transient failure to the caller. If the stream continues to fail and the record cannot be written, the handler must report the failure to the caller rather than silently treating the record as successfully logged.
