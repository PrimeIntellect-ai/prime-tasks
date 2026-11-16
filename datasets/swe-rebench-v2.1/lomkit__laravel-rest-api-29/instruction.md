Better validation errors
### Description

Many errors keys doesn't fully provide the path but the message does. This is due to using rules class.

For example:

```php
$response->assertStatus(422);
$response->assertJsonStructure(['message', 'errors' => ['instructions.0']]);
```
