fix(anta.tests): VerifyVxlan1ConnSettings test should support dps interfaces as source interface
wan2-dc1(config-if-Vx1)#vxlan source-interface ?
  Dps       DPS Tunnel Interface
  Loopback  Hardware interface used for looping packets

### Additional contract requirements

The VXLAN connection-settings verifier must accept `Dps1` as a source interface and verify that the configured source matches the expected source.
