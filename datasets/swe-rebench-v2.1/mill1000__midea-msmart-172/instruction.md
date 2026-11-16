Format of real time power data is device dependent
It appears that the real time power (and maybe energy consumption) data can come in different data formats and scales.

This was always a risk based on the code in georgezhao2010/midea_ac_lan and the variability between the plugin and Lua.

This user reports needing a scaling of 1000 on the power data: https://github.com/mill1000/midea-ac-py/issues/194

This user needs the data to be processed as binary instead of BCD: https://github.com/mill1000/midea-msmart/pull/116#issuecomment-2241536091

### Additional contract requirements

- The reported 1000 scaling applies to the legacy BCD decoding of the real-time power field. The field is reported in Watts and is decoded from the three payload bytes as ``1000 * b0 + 10 * b1 + 0.1 * b2``, where ``b0``, ``b1`` and ``b2`` are the BCD-decoded byte values. For example, the bytes ``01 23 45`` decode to ``1234.5`` W.
- When ``AirConditioner.use_alternate_energy_format`` is ``True``, the device's total energy, current energy, and real-time power readings must use the corresponding binary-format readings: ``EnergyUsageResponse.total_energy_binary``, ``EnergyUsageResponse.current_energy_binary``, and ``EnergyUsageResponse.real_time_power_binary``. Report the energy readings in kWh and power in W. When the setting is ``False``, use the legacy BCD readings. The binary energy fields are unsigned four-byte big-endian values divided by 10; the binary power field is an unsigned three-byte big-endian value divided by 10.
- ``AirConditioner.use_alternate_energy_format`` defaults to ``False`` (legacy BCD format). Its getter returns the value most recently assigned through the setter.
