[Device Support Request] _TZE200_pay2byax
### Problem description

I found the model and manufacturer mentioned here under temp/humidity??

https://github.com/zigpy/zha-device-handlers/blob/57bcec8cf963499b9fca76484619ec57e4a7c088/zhaquirks/tuya/ts0601_sensor.py#L84C1-L97C23

The device works for me with that quirk. But there is a duplicate Illuminance entity and the battery type returns 3 AAA instead of the single CR2032 in the device.

So its currently "partially working"


### Solution description

The device should show correct battery type and only a single Illuminance entity.

### Screenshots/Video

<details><summary>Screenshots/Video</summary>

![image](https://github.com/user-attachments/assets/e9c204e0-1cf7-430c-8263-b4f4c6f49f1d)
![image](https://github.com/user-attachments/assets/a601c379-8aaf-4e45-b6ff-a12a9cfb2a12)

</details>


### Device signature

<details><summary>Device signature</summary>

```json
{
  "node_descriptor": {
    "logical_type": 2,
    "complex_descriptor_available": 0,
    "user_descriptor_available": 0,
    "reserved": 0,
    "aps_flags": 0,
    "frequency_band": 8,
    "mac_capability_flags": 128,
    "manufacturer_code": 4742,
    "maximum_buffer_size": 66,
    "maximum_incoming_transfer_size": 66,
    "server_mask": 10752,
    "maximum_outgoing_transfer_size": 66,
    "descriptor_capability_field": 0
  },
  "endpoints": {
    "1": {
      "profile_id": "0x0104",
      "device_type": "0x0402",
      "input_clusters": [
        "0x0000",
        "0x0001",
        "0x0003",
        "0x0400",
        "0x0500",
        "0xef00"
      ],
      "output_clusters": []
    }
  },
  "manufacturer": "_TZE200_pay2byax",
  "model": "TS0601",
  "class": "zigpy.quirks.v2.CustomDeviceV2"
}
```

</details>


### Diagnostic information

<details><summary>Diagnostic information</summary>

```json
[Paste the diagnostic information here]
```

</details>


### Logs

<details><summary>Logs</summary>

```python
[Paste the logs here]
```

</details>


### Custom quirk

<details><summary>Custom quirk</summary>

```python
[Paste your custom quirk here]
```

</details>


### Additional information

The device has been mentioned before here: https://github.com/zigpy/zha-device-handlers/issues/1502

Entity sensor.tze200_pay2byax_ts0601_illuminance_2 (<class 'homeassistant.components.zha.sensor.Sensor'>) is using native unit of measurement 'None' which is not a valid unit for the device class ('illuminance') it is using; expected one of ['lx'];
