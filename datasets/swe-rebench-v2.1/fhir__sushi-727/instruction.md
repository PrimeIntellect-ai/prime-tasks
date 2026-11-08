Error when using inline instance of resource that assigns meta.security
As reported on Zulip [here](), the following FSH causes an error in SUSHI:
```
Instance:   ex-patient2
InstanceOf: Patient
Title:      "Dummy Patient example"
Description: "Dummy patient example for completeness sake. No actual use of this resource other than an example target"
* meta.security = http://terminology.hl7.org/CodeSystem/v3-ActReason#HTEST

Instance:   ex-dummyPatientBundle
InstanceOf: Bundle
Title:      "Dummy Patient feed"
Description: "Example of a patient feed transaction Bundle."
* meta.security = http://terminology.hl7.org/CodeSystem/v3-ActReason#HTEST
* type = #transaction
* timestamp = 2020-11-24T23:50:50-05:00
* entry[0].resource = ex-patient2
* entry[0].fullUrl = "http://www.example.org/fhir/Patient/593cd04e-b696-45c1-bc32-39e55a340a99"
* entry[0].request.url = "Patient"
* entry[0].request.method = #POST
```

The error is:
> error Cannot read property '0' of undefined
