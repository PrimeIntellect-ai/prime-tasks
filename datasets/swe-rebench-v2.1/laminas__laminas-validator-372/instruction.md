Enum-Validator
### Feature Request

I would like to have an enum validator.

|    Q        |   A
|------------ | ------
| New Feature | yes
| RFC         | no
| BC Break    | may be, it depends

#### Summary

Like I have a value and if it is in the specific enum it is valid.

Of course this would be a php > 8.0 feature. So I just want to know if you're open for that or if it is not in the scope of this package.

I you're open for it I will try to add a pull request :-)

### Additional contract requirements

Provide `Laminas\Validator\BackedEnumValue` and `Laminas\Validator\EnumCase` validators, each configured with the enum class in the `enum` option. `BackedEnumValue` determines membership from values of a backed enum, while `EnumCase` determines membership from case names and works with both unit and backed enums. For each validator, an input representing one of the configured enum's relevant values is valid, and a nonmember is invalid. The request does not prescribe how diagnostics are phrased or whether alternate representations such as enum case objects or numeric strings are accepted.
