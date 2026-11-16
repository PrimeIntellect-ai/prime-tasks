Make [WEBSOCKETS] point to WHATWG spec, not dead W3C spec
https://www.specref.org/?q=websockets points to https://www.w3.org/TR/websockets/, which redirects to https://html.spec.whatwg.org/multipage/

It should instead point to https://websockets.spec.whatwg.org/, per https://resources.whatwg.org/biblio.json

### Additional contract requirements

- Also expose `WEBSOCKETS-API` and `WHATWG-WEBSOCKETS` as aliases for `WEBSOCKETS`. Support the dated identifiers `WHATWG-WEBSOCKETS-20090423`, `WHATWG-WEBSOCKETS-20091029`, `WHATWG-WEBSOCKETS-20091222`, `WHATWG-WEBSOCKETS-20110419`, `WHATWG-WEBSOCKETS-20110929`, `WHATWG-WEBSOCKETS-20111208`, `WHATWG-WEBSOCKETS-20120524`, `WHATWG-WEBSOCKETS-20120809`, `WHATWG-WEBSOCKETS-20120920`, and `WHATWG-WEBSOCKETS-20210128`; for each date, `WEBSOCKETS-<date>` and `WEBSOCKETS-API-<date>` must resolve to the corresponding dated reference.
