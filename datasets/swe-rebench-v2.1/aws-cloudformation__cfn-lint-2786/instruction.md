Alert when doing a split on a dynamic reference
You can dynamic reference a `StringList` but it is read in as a comma delimited singular string. [Docs](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/dynamic-references.html#dynamic-references-ssm)

You cannot put it back into a list by doing `!Split [',', '{{resolve:ssm:/vpc/subnets/private}}']` because the split is done prior to the dynamic reference.  This will result in a singular string that is comma delimited.

As a reference `!Split [':', '{{resolve:ssm:/vpc/subnets/private}}']` will split this string into a list of 3 strings.
