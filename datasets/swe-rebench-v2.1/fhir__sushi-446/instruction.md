Sushi doesn't like primitives with extensions but no value as a valid instance of the primitive when counting required quantities
This example demonstrates the problem:

Profile: MeasureReportProfile
Parent: MeasureReport
* group.population.count 1..1
* group.population.code 1..1

Instance: SampleMeasureReport
InstanceOf: MeasureReportProfile
* status = #complete
* type = #summary
* measure = "fake"
* period.start = "2020-04-26"
* period.end = "2020-04-26"
* group[0].population.count = 1
* group[0].population.code.coding = http://terminology.hl7.org/CodeSystem/measure-population#measure-population

// The following doesn't get counted as an instance of count, I suspect because in json, this is recorded
// in the _count property since count is a primitive.
* group[0].population[1].count.extension.url = "http://hl7.org/fhir/StructureDefinition/data-absent-reason"
* group[0].population[1].count.extension.valueCode = http://terminology.hl7.org/CodeSystem/data-absent-reason#unsupported

// This, on the other hand, does work, but NOTE that code is CodeableConcept, and so doesn't do the _code weirdness
* group[0].population[1].code.extension.url = "http://hl7.org/fhir/StructureDefinition/data-absent-reason"
* group[0].population[1].code.extension.valueCode = http://terminology.hl7.org/CodeSystem/data-absent-reason#unsupported

If you run just this file, it will barf with:
error Element MeasureReport.group.population.count has minimum cardinality 1 but occurs 0 time(s).
  File: C:\Users\kboone\eclipse-workspace\test\fsh\MissingIntegerTest.fsh
  Line: 6 - 19

But clearly that isn't true.  There really is a count.  Unfortunately, sushi doesn't see it b/c the extension is stored in _count, not in count is a primitive, and primitives have to work another way because "reasons".
