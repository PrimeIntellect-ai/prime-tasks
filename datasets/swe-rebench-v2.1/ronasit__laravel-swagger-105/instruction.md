Configs logic update
1. Use larval application name as a title field
2. Set contact email null by default and throw exception on null value to force developer to set his email

### Additional contract requirements

- The contact email is configured under the `info.contact.email` key of the `auto-doc` configuration, i.e. it is read via `config('auto-doc.info.contact.email')`. The package ships this key with a default value of `null`.
- When the contact email is null, the service throws `RonasIT\Support\AutoDoc\Exceptions\EmptyContactEmailException`.
- The Laravel application name is used as the `info.title` field of the generated documentation.
