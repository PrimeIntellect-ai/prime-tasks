add enums to compiler's context
- add enum definition to source database
   - add enum values definition
- add enum definition validation:
  - error: all enum values must be unique
  - hint: capitalise enum values

### Additional contract requirements

- Expose parsed enum definitions through `ApolloCompiler::enums`; callers can read each enum name with `EnumDefinition::name`, its values with `EnumDefinition::enum_values_definition`, and each value string with `EnumValueDefinition::enum_value`.

- Report duplicate-value errors using `Error(UniqueValue { message: "Enum Definition must have unique values", value: VALUE })`, replacing `VALUE` with the duplicated enum value. Report capitalization hints using `Warning(CapitalizedValue { message: "Enum values are recommended to be capitalized", value: VALUE })`, replacing `VALUE` with the value being warned about.
- An enum value requires a capitalization hint when it is not written entirely in uppercase letters, that is, when it contains at least one lowercase letter. Values consisting only of uppercase letters, digits, and underscores (such as `CAT` or `THRIVE_PET_FOODS`) do not require a hint. Thus mixed-case and lowercase enum values require a hint, while uppercase values such as `FOX` do not.
