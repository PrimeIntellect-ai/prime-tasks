DTO\User loses is_bot=false property when call ...->toArray() method
Hello,

When call `DTO\User` object toArray() method `is_bot = false` property is missing. [HIDDEN]

`vendor/defstudio/telegraph/src/DTO/`
```
public function toArray(): array
    {
        [HIDDEN]
            'id' => $this->id,
            'is_bot' => $this->isBot,
            'first_name' => $this->firstName,
            'last_name' => $this->lastName,
            'username' => $this->username,
            'language_code' => $this->languageCode,
        ]);
    }
```
<img width="911" alt="Screenshot 2023-10-12 at 01 52 32" src="https://github.com/defstudio/telegraph/assets/84812777/79148cd2-296c-49b6-a4c9-bcd8f7c978eb">

<img width="1057" alt="Screenshot 2023-10-12 at 01 57 28" src="https://github.com/defstudio/telegraph/assets/84812777/776de4c9-06c8-4d68-b1e2-aa6e680ab690">

### Additional contract requirements

- When serializing messages returned by polling updates, retain the `protected: false`, `photos: {  }`, and `new_chat_members: {  }` fields. If the sender has empty string values, include `last_name: ''` and `language_code: ''` in its `from` object.
- When a `DTO\User` has `isBot` set to `false`, calling `toArray()` must include the `is_bot` key with the boolean value `false`.
