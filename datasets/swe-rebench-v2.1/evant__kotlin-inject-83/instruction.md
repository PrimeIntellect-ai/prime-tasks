Support annotating constructor with @Inject
Annotating the class selects the primary constructor which is usually what you want, but sometimes you'd want to annotate the constructor explicitly. This is useful if:
1. You have more than one constructor
2. You are migrating dagger code

### Additional contract requirements

- Compilation must fail with diagnostic output containing `Cannot annotate constructor with @Inject in an @Inject-annotated class` when a class annotated with `@Inject` also has an `@Inject`-annotated constructor. Compilation must fail with diagnostic output containing `Class cannot contain multiple @Inject-annotated constructors` when a class has multiple `@Inject`-annotated constructors.
