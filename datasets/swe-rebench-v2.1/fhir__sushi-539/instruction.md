Using local CS in code definition doesn't always work
For example, this produces the error `Resolved value "MyCS" is not a valid URI.`:

```
CodeSystem: MyCS
Id: my-cs
* #mycode "My Display" "My Definition"

Profile: MyProfile
Parent: Patient
* active ^code[0] = MyCS#mycode
```

but if we change it to use an alias instead, it works:

```
CodeSystem: MyCS
Id: my-cs
* #mycode "My Display" "My Definition"

Alias: MyCSAlias = http://hl7.org/fhir/sushi-test/CodeSystem/my-cs

Profile: MyProfile
Parent: Patient
* active ^code[0] = MyCSAlias#mycode
```

Note that these _also_ work (using the CS name, _not_ the alias):

```
Profile: MyOtherProfile
Parent: Observation
* code = MyCS#mycode

Instance: MyInstance
InstanceOf: Observation
* code = MyCS#mycode
```

So this would suggest that this bug may be restricted to using local code systems in codes in caret rules.
