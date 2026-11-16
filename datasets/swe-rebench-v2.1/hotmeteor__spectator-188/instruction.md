Arrays of objects are not correctly parsed in request parameters
When having an array of objects in query string, Spectator cannot validate it properly even if the data is perfectly correct:

```
$this->getJson("api/route?" . Arr::query([
            'periods' => [
                [
                    'date' => '2024-03-11',
                    'start_time' => '08:00:00',
                    'end_time' => '10:00:00',
                ],
                [
                    'date' => '2024-03-12',
                    'start_time' => '10:00:00',
                    'end_time' => '12:00:00',
                ],
            ],
        ]))
        ->assertValidContract();
```

```
All array items must match schema
The data ({type}) must match the type: object

array <== All array items must match schema
    object++ <== The data ({type}) must match the type: object
        date*: string
        start_time*: string
        end_time*: string
```

It looks like
[HIDDEN]
fixes it (in `RequestValidator::validateParameters`)

I don't have the time to send a PR fixing it right now but will do it soon unless someone else does it faster !
