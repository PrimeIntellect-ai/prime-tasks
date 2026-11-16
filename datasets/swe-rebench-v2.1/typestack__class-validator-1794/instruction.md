fix: symbol are not handled as constraint arguments and make message generation raise an error
### Description

When implementing custom validators and using symbols as constraints, an error is raised when the error message is generated for a failed validation.

**Minimal code-snippet showcasing the problem**
<!-- Reports without code examples may be closed without investigating. -->
<!-- Add your code snippet below between the backticks. -->
```ts
const mySymbol = Symbol('mySymbol');

function IsSameType(property: unknown, validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string): void {
    registerDecorator({
      target: object.constructor,
      propertyName: propertyName,
      options: validationOptions,
      constraints: [property],
      validator: {
        validate(value: any, args: ValidationArguments) {
          return typeof value ===  typeof args.constraints[0]
        },
        defaultMessage: buildMessage(
          eachPrefix => eachPrefix + '$property must be of type ' + typeof property,
          validationOptions
        ),
      },
    });
  };
}

class MyClass {
  @IsSameType(mySymbol)
  property: symbol;
}

const model = new MyClass();

// this will raise an error when generating the message
validator.validate(model)
```

### Expected behavior
No error should be raised when generating a failed validation message.

### Actual behavior
An error is raised when generating a failed validation message.
