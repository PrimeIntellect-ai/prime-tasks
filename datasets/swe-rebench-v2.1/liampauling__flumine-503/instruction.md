backtesting: market_book not updating on market.closed = True
```python
for market in framework.markets:
    results = {r.selection_id: r.status for r in market.market_book.runners}
    print(results)

{38432986: 'ACTIVE', 28095515: 'REMOVED', 38235043: 'ACTIVE', 26817710: 'ACTIVE', 36775362: 'ACTIVE', 37487570: 'ACTIVE', 27207443: 'ACTIVE', 10138440: 'ACTIVE', 38648845: 'ACTIVE', 14037512: 'ACTIVE', 36753881: 'ACTIVE', 12829452: 'ACTIVE', 24075586: 'ACTIVE'}
```

https://github.com/liampauling/flumine/blob/ec060b7d98a9f15ec229fab73644d5ad970e05fe/flumine/backtest/backtest.py#L118

### Additional contract requirements

When a backtested market closes, the market’s stored market book must reflect the closing market state, including the runner statuses in that update.
