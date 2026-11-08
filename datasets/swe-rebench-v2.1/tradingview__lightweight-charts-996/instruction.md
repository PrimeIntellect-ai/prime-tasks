`Delegate.unsubscribeAll` method works in opposite way
### Discussed in https://github.com/tradingview/lightweight-charts/discussions/994

<div type='discussions-op-text'>

<sup>Originally posted by **zaleGZL** January 31, 2022</sup>
https://github.com/tradingview/lightweight-charts/blob/1d49f27ce7aa130ae0579dfdbb4ee2b7494c6c4e/src/helpers/delegate.ts#L30

should [HIDDEN]  ?</div>

### Additional contract requirements

- `Delegate.unsubscribeAll(linkedObject)` removes listeners whose linked object equals the supplied value and retains listeners whose linked object does not equal it.
