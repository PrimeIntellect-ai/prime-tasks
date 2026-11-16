error with comparisons with the in statement with version v.0.3.5
### Version Information

* vyper Version: 0.3.5
* OS: Ubuntu 20.04.4 LTS
* Python Version : 3.9.9

### What's your issue about?

it seems there is an error with comparisons with the in statement with version v.0.3.5

the following code:
```vyper
@view
@external
def showError():
    adr1: address = 0xFbEEa1C75E4c4465CB2FCCc9c6d6afe984558E20
    adr2: address = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    adr3: address = 0xFbEEa1C75E4c4465CB2FCCc9c6d6afe984558E20
    assert adr1 in [adr2,adr3], "error in comparison with in statement!"
```

works fine with version 0.3.4
adr1 in [adr2,adr3] == True --> this is correct!

with version 0.3.5 the assertion fails, but that is a bug because adr1 == adr3 so the result of the comparison should be true.
adr1 in [adr2,adr3] == False --> this is not correct!
