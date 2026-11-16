XSD DataTime with T24:00:00 not adjusted
### Version

5.2.0

### What happened?

```sh
qexpr '"1999-12-31T24:00:00"^^xsd:dateTime = "2000-01-01T00:00:00"^^xsd:dateTime'
```
should be true.



### Relevant output and stacktrace

_No response_

### Are you interested in making a pull request?

Yes
