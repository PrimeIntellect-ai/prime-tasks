Bug in SpecialFunctions.Hypotenuse
Hello, the implementation of Hypotenuse is buggy. The following test fails:

```
[Fact]
void TestHypotenuse()
{
  Assert.True(double.IsNaN(SpecialFunctions.Hypotenuse(double.NaN, 0)));
}
```

This has severe consequences, because e.g. the following test also fails:

```
 [Fact]
 void TestL2Norm()
 {
   var v = Vector<double>.Build.Dense([double.NaN, 0]);
   Assert.True(double.IsNaN(v.L2Norm()));
 }
```

Best regards, Dirk
