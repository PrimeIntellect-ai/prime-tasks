SUSHI drops resource extensions when generating IG JSON
To support "adjunct binary" loading with `Binary` resources, you must add an extension to the resource description in the IG JSON file.  You should be able to do this in sushi-config.yaml, but it seems that the extension is not coming through.

The attached zip (a modified version of an excellent example John Moerke provided), demonstrates the problem.  When you run it through SUSHI, the resulting IG JSON does _not_ have the resource extension in it.  As a result, when you run IG Publisher, the binary example is not processed correctly and has an error in the qa.html.

[testBinary.zip](https://github.com/FHIR/sushi/files/7822530/testBinary.zip)

I expected this to work, as resource extensions are an important part of the logical model examples workflow documented in the [SUSHI 2.2.0 release notes](https://github.com/FHIR/sushi/releases/tag/v2.2.0).

Zulip 1: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Binary.20Adjunct/near/266507118
Zulip 2: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/.22Big.20data.22/near/266809120
Zulip 3: https://chat.fhir.org/#narrow/stream/179252-IG-creation/topic/binary.20resources/near/264207318
