Serialize/deserialize negative Decimal number  is wrong
Hi,

I extracted codes from `DataTypeDecimal`,  The following is the test codes:

```JAVA
    @Test
    public void testNegativeDecimal() {
        //
        int scale = 4;
        BigDecimal negative = new BigDecimal("-18.2000");
        BigDecimal scaleFactor = BigDecimal.valueOf(Math.pow(10, scale));
        BigDecimal targetValue = negative.multiply(scaleFactor);
        BigInteger res = targetValue.toBigInteger();

        long l1 = res.longValue();
        long l2 = res.shiftRight(64).longValue();

        BigInteger v1 = new BigInteger(1, longToBytes(l1));
        BigInteger v2 = new BigInteger(1, longToBytes(l2));

        BigDecimal value = new BigDecimal(v1.add(v2.shiftLeft(64)));
        value = value.divide(scaleFactor, scale, RoundingMode.HALF_UP);

        Assert.assertEquals(negative, value);
    }
```

and the result is:

```
java.lang.AssertionError:
Expected :-18.2000
Actual   :34028236692093846346337460743176802.9456
```
