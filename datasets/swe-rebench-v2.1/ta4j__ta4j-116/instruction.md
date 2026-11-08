Add valueOf(BigDecimal) and toBigDecimal() methods in Decimal.java
I have the OHLC (ticks) data provided with BigDecimal values. To create a ta4j Tick I need to convert the values into Decimal.java with the valueOf(String):

```
BigDecimal low; // ohlc data
...
// Create a Tick
Decimal.valueOf(low.toString())
...
```
There is a constructor that uses a BigDecimal but it is private.

And then if I want to use a BigDecimal from an indicator, I need to convert the Decimal to String, and then convert the String into BigDecimal:
```
return new BigDecimal(new SMAIndicator(new ClosePriceIndicator(series), 5).getValue(42).toString())
```

It can be boilerplate considering that `Decimal` is backed by a `BigDecimal`, but I don't know if it is on purpose or not.

### Additional contract requirements

The public API required by this task consists of exactly these two members on `org.ta4j.core.Decimal`:

- `public static Decimal valueOf(BigDecimal val)` — creates a `Decimal` that wraps the supplied `BigDecimal`, preserving its exact value and scale (no rounding and no loss of precision).
- `public BigDecimal getDelegate()` — an instance method that returns the underlying `BigDecimal` backing this `Decimal`, preserving its exact value and scale. This method is the required Decimal-to-BigDecimal conversion; the conversion referred to as `toBigDecimal()` in the title is exposed under the public name `getDelegate()`.
