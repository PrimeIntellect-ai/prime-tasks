Keep settings and states in sync between EVSE and EVCC
Major settings like charge current and charge enabled should be kept in sync between internal EVCC and EVSE.

Due to any connection problem (shutdown or reboot of EVSE, bad wireless connection, EMP, manual settings on EVSE, internal EVSE logic etc.) settings can be desynced between EVCCs will and what the charger really does.
So EVCC should read the major settings from EVSE, compare and update them if they differ on a regular base where possible. Not all types of EVSE allow for reading the internal settings.

Appart from that it should make sure that the connection to EVSE is alive by implementing something like "heartbeat" or "ping" to monitor the connection #122

### Additional contract requirements

- The synchronization requirement applies to the charger's enabled state, which is the only setting the charger interface exposes for reading. On each update while the EVSE is connected, EVCC reads the charger's enabled state via `Charger.Enabled() (bool, error)` and, when it differs from EVCC's internal enabled state, corrects the charger via `Charger.Enable(enabled bool) error` so that the charger matches EVCC's state. Charge current is only writable via `Charger.MaxCurrent(current int64) error` and cannot be read back from the charger, so it is not part of the synchronization requirement.
