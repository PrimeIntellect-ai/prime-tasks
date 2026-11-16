References to contained resources
If you run SUSHI on the following snippet of FSH:
```
Instance: Foo
InstanceOf: ServiceRequest
* contained = annexSR2
* supportingInfo = Reference(annexSR2)

Instance: annexSR2
InstanceOf: Binary
Usage: #inline
* contentType = #zip
```
The output JSON has `supportingInfo.reference` set to `Binary/annexSR2`. The IG Publisher issues errors in the QA report, because `Binary/annexSR2` cannot be resolved, since it is an inline defined contained resource, so it does not exist on its own. Instead, the reference should be set as `#annexSR2` to keep the IG Publisher happy.
