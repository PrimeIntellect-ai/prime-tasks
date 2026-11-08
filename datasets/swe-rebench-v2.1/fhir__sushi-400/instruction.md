Sushi is generating arrays for Reference.identifier
Sushi lets me do this to MeasureReport:

* subject.identifier 1..*
* subject.identifier ^short = "The subject shall have at least one identifier which uniquely identifies the subject to the recepient."
* subject.identifier ^comment = "Requiring subject.identifier allows reports to be queried by locations using a well-known identifier."

And then in instances, creates an array for subject.identifier.

But subject.identifier in the base is 0..1

It should barf at me trying to extend beyond cardinality of 1 for subject.identifier
