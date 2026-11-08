[Device Support Request] Sonoff SNZB-01P (new style button)
### Problem description

Sonoff has a new button called SNZB-01P that uses a different housing design. It looks generally software compatible with the old SNZB-01 so the existing quirk code might work with it.

### Solution description

Support for "toggle", "on", and "off" events from this device.

### Screenshots/Video

_No response_

### Device signature

<details><summary>Device signature</summary>

```json
{
  "node_descriptor": "NodeDescriptor(logical_type=<LogicalType.EndDevice: 2>, complex_descriptor_available=0, user_descriptor_available=0, reserved=0, aps_flags=0, frequency_band=<FrequencyBand.Freq2400MHz: 8>, mac_capability_flags=<MACCapabilityFlags.AllocateAddress: 128>, manufacturer_code=4742, maximum_buffer_size=82, maximum_incoming_transfer_size=255, server_mask=11264, maximum_outgoing_transfer_size=255, descriptor_capability_field=<DescriptorCapability.NONE: 0>, *allocate_address=True, *is_alternate_pan_coordinator=False, *is_coordinator=False, *is_end_device=True, *is_full_function_device=False, *is_mains_powered=False, *is_receiver_on_when_idle=False, *is_router=False, *is_security_capable=False)",
  "endpoints": {
    "1": {
      "profile_id": "0x0104",
      "device_type": "0x0000",
      "input_clusters": [
        "0x0000",
        "0x0001",
        "0x0003",
        "0x0020",
        "0xfc57"
      ],
      "output_clusters": [
        "0x0003",
        "0x0006",
        "0x0019"
      ]
    }
  },
  "manufacturer": "eWeLink",
  "model": "SNZB-01P",
  "class": "zigpy.device.Device"
}
```

</details>


### Diagnostic information

<details><summary>Diagnostic information</summary>

```json
{
  "home_assistant": {
    "installation_type": "Home Assistant Supervised",
    "version": "2023.10.4",
    "dev": false,
    "hassio": true,
    "virtualenv": false,
    "python_version": "3.11.5",
    "docker": true,
    "arch": "x86_64",
    "timezone": "America/New_York",
    "os_name": "Linux",
    "os_version": "5.10.0-20-amd64",
    "supervisor": "2023.10.1",
    "host_os": "Debian GNU/Linux 11 (bullseye)",
    "docker_version": "20.10.22",
    "chassis": "vm",
    "run_as_root": true
  },
  "custom_components": {
    "hacs": {
      "version": "1.32.1",
      "requirements": [
        "aiogithubapi>=22.10.1"
      ]
    },
    "frigate": {
      "version": "4.0.0",
      "requirements": [
        "pytz==2022.7"
      ]
    }
  },
  "integration_manifest": {
    "domain": "zha",
    "name": "Zigbee Home Automation",
    "after_dependencies": [
      "onboarding",
      "usb"
    ],
    "codeowners": [
      "@dmulcahey",
      "@adminiuga",
      "@puddly"
    ],
    "config_flow": true,
    "dependencies": [
      "file_upload"
    ],
    "documentation": "https://www.home-assistant.io/integrations/zha",
    "iot_class": "local_polling",
    "loggers": [
      "aiosqlite",
      "bellows",
      "crccheck",
      "pure_pcapy3",
      "zhaquirks",
      "zigpy",
      "zigpy_deconz",
      "zigpy_xbee",
      "zigpy_zigate",
      "zigpy_znp",
      "universal_silabs_flasher"
    ],
    "requirements": [
      "bellows==0.36.7",
      "pyserial==3.5",
      "pyserial-asyncio==0.6",
      "zha-quirks==0.0.105",
      "zigpy-deconz==0.21.1",
      "zigpy==0.57.2",
      "zigpy-xbee==0.18.3",
      "zigpy-zigate==0.11.0",
      "zigpy-znp==0.11.6",
      "universal-silabs-flasher==0.0.14",
      "pyserial-asyncio-fast==0.11"
    ],
    "usb": [
      {
        "vid": "10C4",
        "pid": "EA60",
        "description": "*2652*",
        "known_devices": [
          "slae.sh cc2652rb stick"
        ]
      },
      {
        "vid": "1A86",
        "pid": "55D4",
        "description": "*sonoff*plus*",
        "known_devices": [
          "sonoff zigbee dongle plus v2"
        ]
      },
      {
        "vid": "10C4",
        "pid": "EA60",
        "description": "*sonoff*plus*",
        "known_devices": [
          "sonoff zigbee dongle plus"
        ]
      },
      {
        "vid": "10C4",
        "pid": "EA60",
        "description": "*tubeszb*",
        "known_devices": [
          "TubesZB Coordinator"
        ]
      },
      {
        "vid": "1A86",
        "pid": "7523",
        "description": "*tubeszb*",
        "known_devices": [
          "TubesZB Coordinator"
        ]
      },
      {
        "vid": "1A86",
        "pid": "7523",
        "description": "*zigstar*",
        "known_devices": [
          "ZigStar Coordinators"
        ]
      },
      {
        "vid": "1CF1",
        "pid": "0030",
        "description": "*conbee*",
        "known_devices": [
          "Conbee II"
        ]
      },
      {
        "vid": "10C4",
        "pid": "8A2A",
        "description": "*zigbee*",
        "known_devices": [
          "Nortek HUSBZB-1"
        ]
      },
      {
        "vid": "0403",
        "pid": "6015",
        "description": "*zigate*",
        "known_devices": [
          "ZiGate+"
        ]
      },
      {
        "vid": "10C4",
        "pid": "EA60",
        "description": "*zigate*",
        "known_devices": [
          "ZiGate"
        ]
      },
      {
        "vid": "10C4",
        "pid": "8B34",
        "description": "*bv 2010/10*",
        "known_devices": [
          "Bitron Video AV2010/10"
        ]
      }
    ],
    "zeroconf": [
      {
        "type": "_esphomelib._tcp.local.",
        "name": "tube*"
      },
      {
        "type": "_zigate-zigbee-gateway._tcp.local.",
        "name": "*zigate*"
      },
      {
        "type": "_zigstar_gw._tcp.local.",
        "name": "*zigstar*"
      },
      {
        "type": "_uzg-01._tcp.local.",
        "name": "uzg-01*"
      },
      {
        "type": "_slzb-06._tcp.local.",
        "name": "slzb-06*"
      }
    ],
    "is_built_in": true
  },
  "data": {
    "ieee": "**REDACTED**",
    "nwk": 15051,
    "manufacturer": "eWeLink",
    "model": "SNZB-01P",
    "name": "eWeLink SNZB-01P",
    "quirk_applied": false,
    "quirk_class": "zigpy.device.Device",
    "manufacturer_code": 4742,
    "power_source": "Battery or Unknown",
    "lqi": 42,
    "rssi": null,
    "last_seen": "2023-10-29T11:18:34",
    "available": true,
    "device_type": "EndDevice",
    "signature": {
      "node_descriptor": "NodeDescriptor(logical_type=<LogicalType.EndDevice: 2>, complex_descriptor_available=0, user_descriptor_available=0, reserved=0, aps_flags=0, frequency_band=<FrequencyBand.Freq2400MHz: 8>, mac_capability_flags=<MACCapabilityFlags.AllocateAddress: 128>, manufacturer_code=4742, maximum_buffer_size=82, maximum_incoming_transfer_size=255, server_mask=11264, maximum_outgoing_transfer_size=255, descriptor_capability_field=<DescriptorCapability.NONE: 0>, *allocate_address=True, *is_alternate_pan_coordinator=False, *is_coordinator=False, *is_end_device=True, *is_full_function_device=False, *is_mains_powered=False, *is_receiver_on_when_idle=False, *is_router=False, *is_security_capable=False)",
      "endpoints": {
        "1": {
          "profile_id": "0x0104",
          "device_type": "0x0000",
          "input_clusters": [
            "0x0000",
            "0x0001",
            "0x0003",
            "0x0020",
            "0xfc57"
          ],
          "output_clusters": [
            "0x0003",
            "0x0006",
            "0x0019"
          ]
        }
      },
      "manufacturer": "eWeLink",
      "model": "SNZB-01P"
    },
    "active_coordinator": false,
    "entities": [
      {
        "entity_id": "button.ewelink_snzb_01p_identify",
        "name": "eWeLink SNZB-01P"
      },
      {
        "entity_id": "sensor.ewelink_snzb_01p_battery",
        "name": "eWeLink SNZB-01P"
      }
    ],
    "neighbors": [],
    "routes": [],
    "endpoint_names": [
      {
        "name": "ON_OFF_SWITCH"
      }
    ],
    "user_given_name": null,
    "device_reg_id": "96ad04d2cc5fa845b01eb53e221010f0",
    "area_id": null,
    "cluster_details": {
      "1": {
        "device_type": {
          "name": "ON_OFF_SWITCH",
          "id": 0
        },
        "profile_id": 260,
        "in_clusters": {
          "0x0000": {
            "endpoint_attribute": "basic",
            "attributes": {
              "0x0004": {
                "attribute_name": "manufacturer",
                "value": "eWeLink"
              },
              "0x0005": {
                "attribute_name": "model",
                "value": "SNZB-01P"
              }
            },
            "unsupported_attributes": {}
          },
          "0x0001": {
            "endpoint_attribute": "power",
            "attributes": {
              "0x0021": {
                "attribute_name": "battery_percentage_remaining",
                "value": 200
              },
              "0x0020": {
                "attribute_name": "battery_voltage",
                "value": 32
              }
            },
            "unsupported_attributes": {
              "0x0031": {
                "attribute_name": "battery_size"
              },
              "0x0033": {
                "attribute_name": "battery_quantity"
              }
            }
          },
          "0x0003": {
            "endpoint_attribute": "identify",
            "attributes": {},
            "unsupported_attributes": {}
          },
          "0x0020": {
            "endpoint_attribute": "poll_control",
            "attributes": {
              "0x0000": {
                "attribute_name": "checkin_interval",
                "value": 13200
              }
            },
            "unsupported_attributes": {}
          },
          "0xfc57": {
            "endpoint_attribute": "manufacturer_specific",
            "attributes": {},
            "unsupported_attributes": {}
          }
        },
        "out_clusters": {
          "0x0003": {
            "endpoint_attribute": "identify",
            "attributes": {},
            "unsupported_attributes": {}
          },
          "0x0006": {
            "endpoint_attribute": "on_off",
            "attributes": {},
            "unsupported_attributes": {}
          },
          "0x0019": {
            "endpoint_attribute": "ota",
            "attributes": {},
            "unsupported_attributes": {}
          }
        }
      }
    }
  }
}
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

Event dumps:

```
event_type: zha_event
data:
  device_ieee: 84:ba:20:ff:fe:dc:2e:9a
  unique_id: 84:ba:20:ff:fe:dc:2e:9a:1:0x0006
  device_id: 96ad04d2cc5fa845b01eb53e221010f0
  endpoint_id: 1
  cluster_id: 6
  command: toggle
  args: []
  params: {}
origin: LOCAL
time_fired: "2023-10-29T15:17:03.784569+00:00"
context:
  id: 01HDY05358317YZ0NJ8ES32KQA
  parent_id: null
  user_id: null

event_type: zha_event
data:
  device_ieee: 84:ba:20:ff:fe:dc:2e:9a
  unique_id: 84:ba:20:ff:fe:dc:2e:9a:1:0x0006
  device_id: 96ad04d2cc5fa845b01eb53e221010f0
  endpoint_id: 1
  cluster_id: 6
  command: "on"
  args: []
  params: {}
origin: LOCAL
time_fired: "2023-10-29T15:18:21.179318+00:00"
context:
  id: 01HDY07EQV876Y5V613KK6CH84
  parent_id: null
  user_id: null

event_type: zha_event
data:
  device_ieee: 84:ba:20:ff:fe:dc:2e:9a
  unique_id: 84:ba:20:ff:fe:dc:2e:9a:1:0x0006
  device_id: 96ad04d2cc5fa845b01eb53e221010f0
  endpoint_id: 1
  cluster_id: 6
  command: "off"
  args: []
  params: {}
origin: LOCAL
time_fired: "2023-10-29T15:18:34.012668+00:00"
context:
  id: 01HDY07V8WVTYR1YV5G690K7EQ
  parent_id: null
  user_id: null
```

### Additional contract requirements

- Add a public class `SonoffSmartButtonSNZB01P` in module `zhaquirks.sonoff.snzb01p`.
- The class provides a `replacement` mapping that defines the device's replacement definition, including its endpoints.
- The class provides `device_automation_triggers` with exactly three entries, keyed by the standard `SHORT_PRESS`, `DOUBLE_PRESS` and `LONG_PRESS` constants paired with the `BUTTON` identifier. Each trigger maps to an On/Off cluster command, and the three triggers together cover the `toggle`, `on` and `off` commands.
