groupByTransform(_).getOrDefault(_, KtList.empty()) crashes always
As groupByTransform [HIDDEN]. when `getOrDefault(key, KtList.empty())` is used on returned map from groupByTransform. It crashes with error `type 'EmptyList<Currency>' is not a subtype of type 'KtMutableList<Currency>' of 'defaultValue'`

Reproducible code
```dart
main() {
  var usd = Currency(1, "USD");
  var inr = Currency(2, "INR");
  KtList<Currency> currency = listOf(usd, inr);
  KtList<CurrencyConversionData> conversion =
      listOf(CurrencyConversionData(1, 2));
  KtMap<Currency, KtList<Currency>> conversions =
      _toCurrencyMap(conversion, currency);

  print(conversions.getOrDefault(Currency(1, "USD"), KtList.empty())); // CRASH HERE (type 'EmptyList<Currency>' is not a subtype of type 'KtMutableList<Currency>' of 'defaultValue')
}

KtMap<Currency, KtList<Currency>> _toCurrencyMap(
    KtList<CurrencyConversionData> conversion, KtList<Currency> currency) {
  KtMap<int, Currency> currencyMap = currency.associateBy((cur) => cur.id);
  return conversion.groupByTransform(
    (conv) => currencyMap.get(conv.fromRef)!,
    (conv) => currencyMap.get(conv.toRef)!,
  );
}

class Currency {
  final int id;
  final String ticker;

  Currency(this.id, this.ticker);
}

class CurrencyConversionData {
  final int fromRef;
  final int toRef;

  CurrencyConversionData(this.fromRef, this.toRef);
}

```

### Additional contract requirements

- When a key is absent from a map returned by `groupByTransform`, calling `getOrDefault` with a `KtList.empty()` fallback must not throw and must return that fallback.
