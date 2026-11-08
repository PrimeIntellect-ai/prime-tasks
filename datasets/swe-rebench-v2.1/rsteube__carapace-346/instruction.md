powershell: comma not unescaped during multiparts completion
When unquoted word with escaped comma is completed the escape character is kept although the word is quoted.

```sh
example multiparts --comma first`,<TAB>
# example multiparts --comma 'first`,second,'
```
