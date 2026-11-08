[QUESTION] Support for PartialPaymentAmount in SpecifiedTradePaymentTerms
Hello,

I am using the EN16931 Extended format and trying to set `PartialPaymentAmount `on `SpecifiedTradePaymentTerms`, but I can't find any way to do this.

<img width="326" alt="Image" src="https://github.com/user-attachments/assets/af5360e5-6efa-4956-a4a9-593353fdf4be" />

```
$document = ZugferdDocumentBuilder::CreateNew(ZugferdProfiles::PROFILE_EXTENDED);
$document->addDocumentPaymentTerm(
     $description,
     $dueDate,
     $directDebitMandateID
);
```

Under` horstoeko\zugferd\entities\extended\ram`, there is a class `TradePaymentTermsType` that represents all `SpecifiedTradePaymentTerms` nodes, but how can I use this?

Any guidance would be appreciated.

Thank you!

### Additional contract requirements

- Add a public method `addDocumentPaymentTerm(?string $description = null, ?DateTime $dueDate = null, ?string $directDebitMandateID = null, ?float $partialPaymentAmount = null): ZugferdDocumentBuilder` in `horstoeko\zugferd\ZugferdDocumentBuilder`. The optional fourth argument is the amount of a partial payment (BT-X-275). When a non-null amount is supplied, the generated document contains a `PartialPaymentAmount` element on the payment terms. This is only available in the EXTENDED profile; for other profiles the amount is not written. The method returns the same `ZugferdDocumentBuilder` instance so that calls can be chained.
- Add a public method `getTradePaymentTermsType(?string $description = null, ?DateTime $dueDate = null, ?string $directDebitMandateID = null, ?float $partialPaymentAmount = null): ?object` in `horstoeko\zugferd\ZugferdObjectHelper`. It returns a payment-terms object populated with the supplied values, including the partial-payment amount when a non-null amount is provided.
