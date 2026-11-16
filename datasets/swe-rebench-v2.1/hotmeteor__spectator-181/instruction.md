No response object matching returned status code [200] when 201 is expected
I'm being told that there's no 200 status code so a test is failing, but it actually is responding with a 200. It's meant to be 201, which is what my test is checking for (my controller was wrong).

```
  • Tests\Feature\OrdersCreateTest > it creates an order
   ErrorException

  No response object matching returned status code [200].
Failed asserting that true is false.

  at tests/Feature/OrdersCreateTest.php:39
     35▕         ->postJson('/orders/', [
     36▕             'orderedTrees' => 1,
     37▕         ])
     38▕         ->assertValidRequest()
  ➜  39▕         ->assertValidResponse(201);
     40▕ });
     41▕

  1   tests/Feature/OrdersCreateTest.php:39
      Illuminate\Testing\TestResponse::__call()
```


So Spectator is detecting the response doesn't match the expectated status code, its just reporting it wrong in the error message.

```

it('creates an order', function () {
    $this
        ->withToken($this->api_key)
        ->postJson('/orders/', [
            'orderedTrees' => 1,
        ])
        ->assertValidRequest()
        ->assertValidResponse(201);
});
```
