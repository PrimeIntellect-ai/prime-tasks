Enhancement: pydantic: allow to use examples attribute of the field
### Summary

Pydantic allows to specify example values. It is very good for fields like city or country or currency. It gives very realistic outputs then.

Then we can use random.choice to choose one of these examples while allowing it to be anything else. This may be an optional feature enabled in the factory for users that want it.

### Basic Example

```
class Payment(BaseModel):
    amount: int = Field(0)
    currency: str = Field(None, examples=['USD', 'EUR', 'INR'])

class PaymentFactory(ModelFactory(Payment)):
    __use_examples__ = True  # default would be false for backwards compatibility
```
```
>>> payment = PaymentFactory.build()
>>> payment
Payment(amount=120, currency="EUR")
```



### Drawbacks and Impact

I see no impact. As it will be an optional feature, it will be backwards compatible.

### Unresolved questions

No questions.
