Multiline strings losing letters
I've noticed that it seems like the leading letters in multiline strings can still get cut off in an unexpected way. I thought we had addressed this before, but maybe I am remembering incorrectly. For example, with the following definition:
```
Profile: CancerRelatedMedicationRequest
Parent: USCoreMedicationRequestProfile
Id: mcode-cancer-related-medication-request
Title: "Cancer-Related Medication Request"
Description: """A record of a medication prescription, administration, or consumption used to treat cancer. The medication may reported by the prescriber, prescribing organization, or patient. It does not have to be directly observed.

Conformance statement:

 MedicationRequest resources associated with an mCODE patient and associated with cancer treatment MUST conform to this profile. Beyond this requirement, a producer of resources SHOULD ensure that any resource instance associated with an mCODE patient that would reasonably be expected to conform to this profile (i.e., a prescription, administration, or medication exposure) SHOULD be published in this form."""
```
The resulting string is:
```
" record of a medication prescription, administration, or consumption used to treat cancer. The medication may reported by the prescriber, prescribing organization, or patient. It does not have to be directly observed.\n\nonformance statement:\n\nMedicationRequest resources associated with an mCODE patient and associated with cancer treatment MUST conform to this profile. Beyond this requirement, a producer of resources SHOULD ensure that any resource instance associated with an mCODE patient that would reasonably be expected to conform to this profile (i.e., a prescription, administration, or medication exposure) SHOULD be published in this form."
```
Notice that the "A" to start the description and the "C" in "Conformance are both cut off. I know we do some processing to remove leading spaces, and the "MedicationRequest resources..." line is unnecessarily indented one space, so I'm guessing that is what causes this, but still even if that space is likely a typo this behavior seems unexpected.

### Additional contract requirements

- When importing a multiline `Description` containing an unindented non-blank line, preserve the leading space on later lines. For the text `A long statement follows this.\n\nLong statement:\n\n This statement is much longer than the previous statement.`, the resulting description must be exactly `A long statement follows this.\n\nLong statement:\n\n This statement is much longer than the previous statement.`
