@JestId annotation not found in super class
I would like to suggest an enhancement.
We have a family of documents which share a number of fields and we wanted to separate out the common fields into a super class from which all document types inherit. Particularly the id-field is common to all document types.
The code which looks for the @JestId annotation does not seem to traverse the class hierarchy up in an attempt to find the annotation?
Btw, spring does it so why don't we?
