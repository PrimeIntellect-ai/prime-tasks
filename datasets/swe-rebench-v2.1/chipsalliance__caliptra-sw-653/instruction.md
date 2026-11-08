Set derive child's target locality to SoC's initial locality in RT
When we call derive child in Caliptra RT after initializing the DPE Instance, we need to make the target locality the SoC's initial locality instead of the current value of 0.

### Additional contract requirements

- After the runtime initializes DPE at boot, the default context it creates must be usable by the SoC: a DeriveChild command issued over the mailbox through INVOKE_DPE against the default context, from the SoC's locality, must return a DPE response with status NoError.
- The SoC's initial locality is the PL0 PAUSER value of the firmware image's vendor configuration.
