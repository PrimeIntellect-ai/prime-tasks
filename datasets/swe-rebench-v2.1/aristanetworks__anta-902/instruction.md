Bug: False positive on VerifyNTPAssociation
`show ntp associations | json` can return the following output:
```
DC05-Temp-Bleaf1#sho ntp associations | json
{
    "peers": {
        "10.10.200.22 (ntp.example.com)": {
            "condition": "sys.peer",
            "peerIpAddr": "10.10.200.22",
            "refid": "164.100.255.122",
            "stratumLevel": 3,
            "peerType": "unicast",
            "lastReceived": 1730124132.0,
            "pollInterval": 1024,
            "reachabilityHistory": [
                true,
                true,
                true,
                true,
                true,
                true,
                true,
                true
            ],
            "delay": 0.524,
            "offset": 5.545,
            "jitter": 3.8
        }
    }
}
```
The FQDN of the NTP server can be included in parentheses. The test logic should be updated accordingly.

### Additional contract requirements

- For an association mismatch, the failure message must use this exact format: `{NTPServer.__str__()} - Bad association; Condition: {actual_condition}, Stratum: {actual_stratum}`. For example: `1.1.1.1 (Preferred: True, Stratum: 1) - Bad association; Condition: candidate, Stratum: 2`.
- When no NTP peers are configured, the failure message must be exactly `No NTP peers configured`. When an expected NTP server is not configured, its failure message must be exactly `{NTPServer.__str__()} - Not configured`.
