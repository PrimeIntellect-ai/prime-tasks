@Any qualifier not added automatically by mock bean builder
A bean created with the following code:
```java
MockBean.builder()
        .scope(ApplicationScoped)
        .types(new TypeLiteral<ParameterConverter<Object, Object>>() { }.type)
        .qualifiers(new ParameterType.Literal('foo'))
        .creating(fooParameterConverter)
        .build();
```
will not be injected into an injection point that uses the `@Any` qualifier like
```java
@Inject
@Any
private Instance<ParameterConverter<?, ?>> parameterConverters;
```

I just had a hard time understanding why this is the case.
Shouldn't the `@Any` qualifier always be added implicitly to a bean like the CDI spec defines?

Work-around is to manually add the `@Any` qualifier like `.qualifiers(Any.Literal.INSTANCE, new ParameterType.Literal('foo'))`

### Additional contract requirements

- A `MockBean` built with caller-supplied qualifiers must keep those qualifiers and additionally expose `@Any`, so the bean can be selected both with the caller's qualifier and with `@Any`.
