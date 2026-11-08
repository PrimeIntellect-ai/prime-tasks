Diktat should avoid fixing/raising a warning an issue for overriden contructor arguments
We should not suggest a `@param` Kdoc for the following code:

```
public class Ktoml(
    override val serializersModule: SerializersModule = EmptySerializersModule
)
```
