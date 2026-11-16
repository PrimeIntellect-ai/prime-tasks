Value Energy wrong for Shelly EM with template shelly-1pm
### Describe the bug

See discussion https://github.com/evcc-io/evcc/discussions/6089

Using a Shelly EM (the simple 2 Channel version) with the template shelly-1pm will give the correct "power" value, but the wrong "energy" value

![image](https://user-images.githubusercontent.com/90329895/217178543-e1edc8d3-bd39-426e-817b-f35d0b44c60b.png)


If I use the template shelly-3em the values "power" and "energy" are correct, but of course there are errors because of missing values, the simple EM can not provide compared to 3EM

![image](https://user-images.githubusercontent.com/90329895/217178877-84234dce-52ea-40d4-b069-47bca42c88cb.png)


Shelly Output:

Shelly Pro 1PM http://192.168.178.64/rpc/shelly.getstatus
[Shelly1PM_status.txt](https://github.com/evcc-io/evcc/files/10672556/Shelly1PM_status.txt)

Shelly EM http://192.168.178.65/status
[ShellyEM_status.txt](https://github.com/evcc-io/evcc/files/10672557/ShellyEM_status.txt)

Solution could be a shelly-em template like shelly-3em without the values for "Current L1...L3", "Voltage L1...L3" and "Power L1...L3"?


### Steps to reproduce

1. create loadpoint using Shelly EM as meter
2. use shelly-1pm template -> get wrong/no energy value
3. use shelly-3em template -> get correct energy value, but of course errors for missing values



### Configuration details

```yaml
uri: 192.168.178.70:7070
interval: 10s

# log settings
log: error
levels:
  core: debug
  lp-1: debug
  lp-2: debug

# meter definitions
meters:
- name: grid
  type: custom
  power:
    source: modbus
    uri: 192.168.178.61:502
    id: 1
    register:
      address: 40073
      type: holding
      decode: int32s
- name: pv
  type: custom
  power:
    source: modbus
    uri: 192.168.178.61:502
    id: 1
    register:
      address: 40067
      type: holding
      decode: int32s
- name: battery
  type: custom
  power:
    source: modbus
    uri: 192.168.178.61:502
    id: 1
    register:
      address: 40069
      type: holding
      decode: int32s
    scale: -1
  soc:
    source: modbus
    uri: 192.168.178.61:502
    id: 1
    register:
      address: 40082
      type: holding
      decode: uint16
- name: wallbox
  type: sma
  uri: 192.168.178.63
- name: shelly_m_heizstab
  type: template
  template: shelly-1pm
  usage: charge
  host: 192.168.178.65
#  user: ***
#  password: ***
#  channel: 0

# charger definitions
chargers:
- name: wallbe
  type: wallbe
  uri: 192.168.178.62:502
- name: shelly_s_heizstab
  type: template
  template: shelly
  host: 192.168.178.64
  standbypower: -5

# vehicle definitions
vehicles:
- name: hyundai
  type: hyundai
  title: Ioniq
  capacity: 38
  phases: 1
  user: ***
  password: ***
  onIdentify:
    mode: pv

- name: renault
  type: renault
  title: Twingo
  user: ***
  password: ***
  capacity: 22
  onIdentify:
    mode: pv
    targetSoC: 80

- name: heizen
  type: custom
  title: Heizstab
  phases: 1
  soc:
    source: js
    script: 50;

# site definition
site:
- title: Home
  meters:
    grid: grid
    pvs:
    - pv
    batteries:
    - battery
  prioritySoC: 30

# loadpoint definition
loadpoints:
- title: Garage
  charger: wallbe
  meter: wallbox
  vehicles:
  - hyundai
  - renault
  mode: pv
  resetOnDisconnect: true
  soc:
    poll:
      mode: connected
      interval: 60m
    estimate: true
  phases: 1
  enable:
    delay: 1m
    threshold: 0
  disable:
    delay: 5m
    threshold: 0
  guardduration: 5m
  mincurrent: 6
  maxcurrent: 16
- title: Heizstab
  charger: shelly_s_heizstab
  meter: shelly_m_heizstab
  vehicles: heizen
  mode: pv
  resetOnDisconnect: true
  phases: 1
  mincurrent: 13
  maxcurrent: 14
  enable:
    threshold: 0
    delay: 30s
  disable:
    delay: 15s
    threshold: 0

# tariff definition
tariffs:
  currency: EUR
  grid:
    type: fixed
    price: 0.2923
  feedin:
    type: fixed
    price: 0.07
```


### Log details

```text
[main  ] INFO 2023/02/07 08:25:37 evcc 0.112.4
[main  ] INFO 2023/02/07 08:25:37 using config file: /etc/evcc.yaml
[main  ] WARN 2023/02/07 08:25:37 `uri` is deprecated and will be ignored. Use `network` instead.
[main  ] INFO 2023/02/07 08:25:37 starting ui and api at :7070
[db    ] INFO 2023/02/07 08:25:37 using sqlite database: /root/.evcc/evcc.db
[lp-1  ] WARN 2023/02/07 08:25:41 poll mode '{connected 1h0m0s}' may deplete your battery or lead to API misuse. USE AT YOUR OWN RISK.
[lp-1  ] WARN 2023/02/07 08:25:41 vehicles option is deprecated
[lp-2  ] WARN 2023/02/07 08:25:41 vehicles option is deprecated
[site  ] WARN 2023/02/07 08:25:41 vehicle 'Heizstab' does not support automatic detection
[site  ] INFO 2023/02/07 08:25:41 site config:
[site  ] INFO 2023/02/07 08:25:41   meters:      grid ✓ pv ✓ battery ✓
[site  ] INFO 2023/02/07 08:25:41     grid:      power ✓ energy ✗ currents ✗
[site  ] INFO 2023/02/07 08:25:41     pv 1:      power ✓ energy ✗ currents ✗
[site  ] INFO 2023/02/07 08:25:41     battery 1: power ✓ energy ✗ currents ✗ soc ✓ capacity ✗
[site  ] INFO 2023/02/07 08:25:41   vehicles:
[site  ] INFO 2023/02/07 08:25:41     vehicle 1: range ✗ finish ✗ status ✗ climate ✗ wakeup ✗
[site  ] INFO 2023/02/07 08:25:41     vehicle 2: range ✓ finish ✓ status ✓ climate ✗ wakeup ✓
[site  ] INFO 2023/02/07 08:25:41     vehicle 3: range ✓ finish ✓ status ✓ climate ✓ wakeup ✓
[lp-1  ] INFO 2023/02/07 08:25:41 loadpoint 1:
[lp-1  ] INFO 2023/02/07 08:25:41   mode:        pv
[lp-1  ] INFO 2023/02/07 08:25:41   charger:     power ✗ energy ✗ currents ✗ phases ✗ wakeup ✗
[lp-1  ] INFO 2023/02/07 08:25:41   meters:      charge ✓
[lp-1  ] INFO 2023/02/07 08:25:41     charge:    power ✓ energy ✓ currents ✓
[lp-2  ] INFO 2023/02/07 08:25:41 loadpoint 2:
[lp-2  ] INFO 2023/02/07 08:25:41   mode:        pv
[lp-2  ] INFO 2023/02/07 08:25:41   charger:     power ✓ energy ✓ currents ✗ phases ✗ wakeup ✗
[lp-2  ] INFO 2023/02/07 08:25:41   meters:      charge ✓
[lp-2  ] INFO 2023/02/07 08:25:41     charge:    power ✓ energy ✓ currents ✗
[lp-1  ] DEBUG 2023/02/07 08:25:41 phase timer inactive
[lp-1  ] DEBUG 2023/02/07 08:25:41 pv timer inactive
[lp-2  ] DEBUG 2023/02/07 08:25:41 phase timer inactive
[lp-2  ] DEBUG 2023/02/07 08:25:41 pv timer inactive
[site  ] DEBUG 2023/02/07 08:25:41 ----
[lp-1  ] DEBUG 2023/02/07 08:25:41 charge power: 6W
[main  ] FATAL 2023/02/07 08:25:41 could not open port- check that evcc is not already running (listen tcp :7070: bind: address already in use)
```


### What type of operating system are you running?

Linux

### Version

evcc version 0.112.4

### Additional contract requirements

When a Shelly EM is used as a meter with the shelly-1pm configuration, its energy reading must be reported correctly. Correcting the energy reading must preserve the device's correctly reported power reading.
