BindsMethodValidator does not account for extension functions
When using `generateDaggerFactories`, this results in anvil failing to compile for a @Binds extension function with no parameters (when Dagger passes), and to pass for a @Binds extension function with a parameter (when Dagger fails).

Thanks @efemoney for [raising the extension use-case](https://github.com/square/anvil/pull/654#issuecomment-1324879737).

### Additional contract requirements

- When Anvil rejects a @Binds extension function with an explicit parameter while generating Dagger factories, the compiler messages must include: `@Binds methods must have exactly one parameter, whose type is assignable to the return type`.
