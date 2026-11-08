Fix misspelling of anomaly
See misspellings in https://github.com/elastic/go-libaudit/search?q=anomoly&unscoped_q=anomoly

### Additional contract requirements

Anomaly events use the category `anomaly`, and anomaly-response events use the category `anomaly-response`. The `aucoalesce` package exports the corresponding event type identifiers `EventTypeAnomaly` and `EventTypeAnomalyResponse`.
