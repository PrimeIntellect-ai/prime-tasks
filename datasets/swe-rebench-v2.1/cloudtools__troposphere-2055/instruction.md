SSM Document Property "Content" also allows plain Strings
Good evening everyone,

This is my first issue report. My apologies for any mistakes I make submitting this.
I'm using troposphere 4.0.2 as it is tagged on GitHub.

https://github.com/cloudtools/troposphere/blob/4.0.2/troposphere/ssm.py
In line 115  the propery "Content" is define as a "dict", but according to the AWS Documentation, it also accepts palin strings.

https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ssm-document.html#cfn-ssm-document-content

I temporarely changed the code and simply used "YAML as a string" inside a JSON CloudFormation Template.
Everything worked as it should and the pre-formatted YAML shows up as the contents of SSM Document.

I'm unclear about how this should be fixed correctly. I simply added the type in the one-line diff below:

```diff
--- ssm.py	2022-06-10 18:28:07.450170572 +0000
+++ ssm.py.new	2022-06-10 18:28:22.186197102 +0000
@@ -112,7 +112,7 @@

     props: PropsDictType = {
         "Attachments": ([AttachmentsSource], False),
-        "Content": (dict, True),
[HIDDEN]
         "DocumentFormat": (str, False),
         "DocumentType": (str, False),
         "Name": (str, False),
```
