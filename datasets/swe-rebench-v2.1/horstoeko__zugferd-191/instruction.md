[FEATURE] Allow adding empty ShipTo nodes to the document without enforcing a TradeParty name
**Describe the feature**

This Issue is a follow-up to #101

I want to create an invoice with a tax exemption for intra-community supply.
The business rule BR-IC-12 states that, therefore, the country code of the ship to address (BT-80) must be set in `/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeDelivery/ram:ShipToTradeParty/ram:PostalTradeAddress/ram:CountryID`

The method `setDocumentShipTo` forces me to provide a name of the `ShipToTradeParty`.
However, according to the ZUGFeRD and X-Rechnung specifications, these fields shall be used if the name is not equal to the buyer's name.

> Das Informationselement ist zu verwenden, wenn der Empfänger vom Erwerber abweicht.
> _X-Rechnung Spec_

> Shall be used if the Deliver to party is different from the Buyer.
> _Factur-X Spec_

**Expected behavior**

Provide a method like `setDocumentShipToAddress` [HIDDEN].

See `src/ZugferdDocumentBuilder.php:1016`

**Additional context**
We could work around this by providing the same name as the buyer.
It might be possible that we get a validation error then.
