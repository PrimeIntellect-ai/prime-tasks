Expression with path to nested set value type builds incorrectly
# Description

When trying to build an expression for input containing nested key path such as `.setTo('complex.nested.attr[1]', 'new value')`, attr[1] is treated as a continuing attribute that generates expression and its values like the following:

## Current Exp

exp:  `... #complex_nested_object[1] = :complex_nested_object[1]`
names:
```
{
  #complex_nested_object[1]: 'complex_nested_object[1]'
}
```
values:
```
{
  :complex_nested_object[1]: '1234'
}
```


## Expected Exp
exp:  `... #complex_nested_object[1] = :complex_nested_object`
names
```
{
  #complex_nested_object: 'complex_nested_object'
}
```
values:
```
{
  :complex_nested_object: '1234'
}
```
