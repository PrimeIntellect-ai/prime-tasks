Evaluation context `merge` implementations should be recursive
If there is a property on this called `myKey`, and it has subkeys, and there's also a property called `myKey` on overridingContext, then the subkeys are lost, instead of merged.

This is un-intuitive and should be correct.

see: https://github.com/open-feature/java-sdk/pull/210/files#r1071367173
