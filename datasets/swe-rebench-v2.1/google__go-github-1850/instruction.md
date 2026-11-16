Audit Log API Returns Non-Standard Timestamp
The GitHub Audit Log API return a Unix timestamp in milliseconds, which the current timestamp unmarshalJSON implementation in go-github does not take into account. An implementation needs to be added to account for the audit log having a millisecond-based timestamp.
