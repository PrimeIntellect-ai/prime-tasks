[BUG] ZugferdSettings::addSpecialDecimalPlacesMap doesn't work for BasisPeriodMeasure
By setting `ZugferdSettings::addSpecialDecimalPlacesMap('/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradePaymentTerms/ram:ApplicableTradePaymentDiscountTerms/ram:BasisPeriodMeasure',0);`
I still get an result like `<ram:BasisPeriodMeasure unitCode="DAY">14.0</ram:BasisPeriodMeasure>`

I can't validate my invoices with an BasisPeriodMeasure having decimals.
The function `ZugferdSettings::addSpecialDecimalPlacesMap()` works fine on different fields, but somehow not on the BasisPeriodMeasure

 Sample code:
 ZugferdSettings::addSpecialDecimalPlacesMap('/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradePaymentTerms/ram:ApplicableTradePaymentDiscountTerms/ram:BasisPeriodMeasure',0);
$document = ZugferdDocumentBuilder::CreateNew(ZugferdProfiles::PROFILE_EXTENDED);
$document->addDocumentPaymentTerm("Fälligkeitsdatum: 05.12.24 ; Skonto 3% bis zum 19.11.24",\DateTime::createFromFormat("d.m.y", "19.11.24"))
    ->addDiscountTermsToPaymentTerms(3,\DateTime::createFromFormat("d.m.y", "05.11.24"), 14, "DAY",2123.53,63.71)
