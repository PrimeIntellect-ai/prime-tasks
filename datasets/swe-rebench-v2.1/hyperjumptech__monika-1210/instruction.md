Asymmetric Recovery
**Describe the bug**
1. When identical probes encounter incident, notifications sent to all of them.
2. But when Recovered, only one notification is sent.

**To Reproduce**
Steps to reproduce the behavior:
1. use the following config:

```yaml
probes:
  - id: 'mock-1'
    name: 'local-test'
    requests:
      - url: http://0.0.0.0:7001/v1/hello
    alerts:
      - assertion: response.status != 200
        message: message 11

  - id: 'mock-2'
    name: 'local-test-no-alert'
    requests:
      - url: http://0.0.0.0:7001/v1/hello

  - id: 'mock-3'
    name: 'local-test-no-alert'
    requests:
      - url: http://0.0.0.0:7001/v1/hello
```

2. Disable the local server (0.0.0.0)
3. Expect 3 incident notifications sent
4. Turn back on the local server (0.0.0.0)
5. Expect 3 recovery notifications sent... but only one received

**Screenshots**
1. Startup and Incident
![image](https://github.com/hyperjumptech/monika/assets/964106/87912cc1-77a6-4585-bb21-e74cc68d5e89)

2. Recovery:
![image](https://github.com/hyperjumptech/monika/assets/964106/a1eb2114-1bd9-4d16-8753-96a3f1ed5bee)

3. Email, startup, incident, recovery notifications.
![image](https://github.com/hyperjumptech/monika/assets/964106/756d1c43-b757-4e24-8eb8-74ae34dfc6c4)

**Desktop (please complete the following information):**
 - OS: Linux Ubuntu 22.04
 -  From src: main brnach

### Additional contract requirements

- Add a public function `addIncident({ alert, probeID, url, createdAt? })` in the module `src/components/downtime-counter`. It registers a downtime incident for the given probe request and returns no value.
- Add a public function `removeIncident({ probeID, url })` in the module `src/components/downtime-counter`. It clears the downtime incident whose probe identifier and request URL both match the given values, leaving every incident that differs in either field untouched, and returns no value.
