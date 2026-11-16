Facade Fake loses macros
When using macros to define global settings (f.e. sasl, serializer) the facade fake does not know about those macros.

Let's assume you have defined a macro like this:
```php
Kafka::macro('producer', function (string $topic) use ($serializer, $sasl) {
    return $this
        ->publishOn($topic)
        ->withSasl($sasl)
        ->usingSerializer($serializer($topic));
});
```

and then you want to test the producing of a message like this

```php
Kafka::fake();

Kafka::producer($topic)->withMessage(new Message(body: $body))->send();

Kafka::assertPublishedOn($topic);
```
the test will fail with the following message:

>  Call to undefined method Junges\Kafka\Support\Testing\Fakes\KafkaFake::producer()

A possible solution would be to forward calls (see this PR in Laravel https://github.com/laravel/framework/pull/45988 which solves the same problem https://github.com/laravel/framework/issues/45986)

I've tried to implement it the same way but I had quite the troubles with it and didn't get it to work :(

Would be really cool if you or somebody else could make this happen
