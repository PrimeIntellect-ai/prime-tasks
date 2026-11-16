C# namespace capitalization for versions is incorrect
The linter just complained about this option:

```proto
option csharp_namespace = "Google.Cloud.SecurityCenter.V1P1Beta1";
````

it thinks it should be:

```proto
option csharp_namespace = "Google.Cloud.SecurityCenter.V1p1Beta1";
````

... which is actually the bug I was trying to fix. In general, the PascalCasing of C# names considers numbers to be word separators, so we'd have `Http2Request` for example, rather than `Http2request`.
