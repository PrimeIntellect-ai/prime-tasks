Overriding approval methods clears all defaults
We had a problem today where a policy added alternate comments for some rules, but expected the default behavior of counting GitHub reviews to still work. With the current implementation, setting any property of the `methods` block removes the defaults for all properties.

Consider setting defaults for fields that are not explicitly set by the policy file to reduce confusion, as the docs imply.
