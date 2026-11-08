der: add `IsConstructed` trait
IMPLICIT decoder requires `Tagged` trait.

https://github.com/RustCrypto/formats/blob/937e611fcbabe929f2ff76320dd33873ea3372dd/der/src/asn1/context_specific.rs#L58-L63

IMPLICIT and EXPLICIT decoders check for constructed bit.
But IMPLICIT depends on `value.tag()` in runtime:
https://github.com/RustCrypto/formats/blob/937e611fcbabe929f2ff76320dd33873ea3372dd/der/src/asn1/context_specific.rs#L69-L70

https://github.com/RustCrypto/formats/blob/937e611fcbabe929f2ff76320dd33873ea3372dd/der/src/asn1/context_specific.rs#L161-L164

I think it should check constructed bit statically, like `FixedTag`.

### Additional contract requirements

- Expose `IsConstructed` as a public trait with an associated Boolean constant named `CONSTRUCTED` that indicates whether the implementing type is encoded with the ASN.1 constructed bit.
