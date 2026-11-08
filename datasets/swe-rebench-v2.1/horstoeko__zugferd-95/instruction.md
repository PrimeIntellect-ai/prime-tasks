[ENHANCEMENT] Issue with Adding Multiple BT-29 Using ->setDocumentSeller() in BASIC Profile
Hi @horstoeko,
**Describe the bug**

In the BASIC profile, I can't add multiple BT-29 with ->setDocumentSeller().
Only the last sellertradeparty taken into account is correct.
```xml
<ram:SellerTradeParty>
        <ram:ID>910</ram:ID>
        <ram:Name>Lieferant GmbH</ram:Name>
        <ram:PostalTradeAddress>
          <ram:CountryID>FR</ram:CountryID>
        </ram:PostalTradeAddress>
        <ram:SpecifiedTaxRegistration>
          <ram:ID schemeID="VA">6</ram:ID>
        </ram:SpecifiedTaxRegistration>
</ram:SellerTradeParty>
```

**To Reproduce**
```php
$document
                ->setDocumentSeller("Lieferant GmbH", "549910")
                ->setDocumentSeller("Lieferant GmbH", "910");
```

### Additional contract requirements

- The reported inability to represent multiple BT-29 (seller) and BT-46 (buyer) identifiers is addressed by two new public methods on `ZugferdDocumentBuilder`:
  - `addDocumentSellerId(string $id)` appends `$id` to the current document header's `SellerTradeParty` ID list.
  - `addDocumentBuyerId(string $id)` appends `$id` to the current document header's `BuyerTradeParty` ID list.
- Each method returns the same `ZugferdDocumentBuilder` instance (`$this`) so calls can be chained.
- Repeated calls to either method accumulate identifiers; previously added identifiers are preserved.
- The existing `setDocumentSeller`/`setDocumentBuyer` setters are not required to accumulate identifiers across calls.
