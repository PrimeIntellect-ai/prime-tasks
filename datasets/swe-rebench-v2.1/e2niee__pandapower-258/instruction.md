State estimation error with bus-bus switches and measurements on each bus
Hi,
i am currently working on a high voltage network with lots of measurements. The bus of the pandapower network represents a busbar in the substation in the real world and the buses were connected with each other through bus-bus switches. The measurement of bus (p, q) represents the power flow on a busbar. However the state estimation module (and similarly in power flow calculation) will merge the buses connected through bb-switch to a single bus and which was not in the _add_measurement function the measurement correctly merged.

I have tried to connect the bus with measurement (and also load or sgens) with lines instead of bb-switches as small impedance. This might be a possibility to solve the issue. However it will be better to leave this subsititution to minimum.

The code for test with a simple four bus network:

```python
import numpy as np
from copy import deepcopy

import pandapower as pp
import pandapower.networks as pn
from pandapower.estimation import estimate as se

def r2(base, v):
    return np.random.normal(base, v)

# 1. Create network
net = pp.create_empty_network()
pp.create_bus(net, name="bus1", vn_kv=10.)
pp.create_bus(net, name="bus2", vn_kv=10.)
pp.create_bus(net, name="bus3", vn_kv=10.)
pp.create_bus(net, name="bus4", vn_kv=110.)
pp.create_ext_grid(net, bus=3, vm_pu=1.01)
pp.create_line_from_parameters(net, 0, 1, 10, r_ohm_per_km=.59, x_ohm_per_km=.35, c_nf_per_km=10.1,
                               max_i_ka=1)
pp.create_line_from_parameters(net, 0, 2, 10, r_ohm_per_km=.59, x_ohm_per_km=.35, c_nf_per_km=10.1,
                               max_i_ka=1)
pp.create_line_from_parameters(net, 1, 2, 10, r_ohm_per_km=.59, x_ohm_per_km=.35, c_nf_per_km=10.1,
                               max_i_ka=1)
pp.create_transformer(net, 3, 0, std_type="40 MVA 110/10 kV")

pp.create_load(net, 0, .350, .100)
pp.create_load(net, 1, .450, .200)
pp.create_load(net, 2, .250, .100)

# Created bb switch and the line will be short circuited (ignored)
pp.create_switch(net, 1, element=2, et='b')

net_meas_on_bb_bus = deepcopy(net)

net_switch_as_impedance = deepcopy(net)
net_switch_as_impedance.switch.at[0 ,"closed"] = False
net_switch_as_impedance.line.at[2, 'length_km'] /= 1000
net_switch_as_impedance_with_meas = deepcopy(net_switch_as_impedance)

pp.runpp(net)
pp.runpp(net_meas_on_bb_bus)
pp.runpp(net_switch_as_impedance)
pp.runpp(net_switch_as_impedance_with_meas)

def create_test_measurement(net, measurement_on_bb_switch_bus=False):
    pp.create_measurement(net, "v", "bus", r2(net.res_bus.vm_pu.iloc[0], .004), .004, element=0)
    pp.create_measurement(net, "v", "bus", r2(net.res_bus.vm_pu.iloc[1], .004), .004, element=1)
    pp.create_measurement(net, "v", "bus", r2(net.res_bus.vm_pu.iloc[3], .004), .004, element=3)

    pp.create_measurement(net, "p", "bus", -r2(net.res_bus.p_mw.iloc[3], .002), .004, element=3)
    pp.create_measurement(net, "q", "bus", -r2(net.res_bus.q_mvar.iloc[3], .002), .004, element=3)

## If measurement on the bus with bb-switch activated, it will incluence the results of the merged bus
    if measurement_on_bb_switch_bus:
        pp.create_measurement(net, "p", "bus", -r2(net.res_bus.p_mw.iloc[2], .002), .004, element=2)
        pp.create_measurement(net, "q", "bus", -r2(net.res_bus.q_mvar.iloc[2], .002), .004, element=2)

    pp.create_measurement(net, "p", "line", r2(net.res_line.p_from_mw.iloc[0], .001), .002, 0, side='from')
    pp.create_measurement(net, "q", "line", r2(net.res_line.q_from_mvar.iloc[0], .001), .002, 0, side='from')
    pp.create_measurement(net, "p", "line", r2(net.res_line.p_from_mw.iloc[1], .001), .002, 1, side='from')
    pp.create_measurement(net, "q", "line", r2(net.res_line.q_from_mvar.iloc[1], .001), .002, 1, side='from')

    pp.create_measurement(net, "p", "trafo", r2(net.res_trafo.p_hv_mw.iloc[0], .002), .01,
                          side="hv", element=0)  # transformer meas.
    pp.create_measurement(net, "q", "trafo", r2(net.res_trafo.q_hv_mvar.iloc[0], .002), .01,
                          side=3, element=0)  # at hv side

create_test_measurement(net)
create_test_measurement(net_switch_as_impedance)
create_test_measurement(net_meas_on_bb_bus, True)
create_test_measurement(net_switch_as_impedance_with_meas, True)

# 2. Do state estimation
success_net = se(net, tolerance=1e-5, maximum_iterations=20)
success_net_meas_on_bb_bus = se(net_meas_on_bb_bus, tolerance=1e-5, maximum_iterations=20)
success_net_with_impedance = se(net_switch_as_impedance, tolerance=1e-5, maximum_iterations=20)
success_impedance_with_meas = se(net_switch_as_impedance_with_meas, tolerance=1e-5, maximum_iterations=20)


res_bus_with_switch = net.res_bus_est
res_bus_meas_on_bb_bus = net_meas_on_bb_bus.res_bus_est
res_bus_small_impedance = net_switch_as_impedance.res_bus_est
res_bus_small_impedance_with_meas = net_switch_as_impedance_with_meas.res_bus_est
```
The network has the following variations:

- original
- bb: using bb-switch between bus 1, 2
- imp: using small impedance instead of bb-switch between bus 1,2
- bb+meas: using bb-switch and has p, q measurement on one of the buses with bb-switch
- imp+meas: using small impedance and has p, q measurement on one of the buses

P_mw injections on buses:

| bus id | Original| bb |  imp |  bb+meas | imp+meas |
|--|--|--|--|--|--|
| 0 | 0.35 | 0.35 | 0.35 | 0.43| 0.35 |
| 1 | 0.45 | 0.7 | 0.05 | 0.62 | 0.45 |
| 2 | 0.25 | 0.7 | 0.65 | 0.62 | 0.25 |
| 3 | -1.09 | -1.09 | -1.08 | -1.09 | -1.08 |

From the result, it seems like that small impedance with measurements delivers the best result. And if the network has bb-switch, the state estimation module seems fail to identify the buses, since it's automatically merged to one bus in ppc.

### Additional contract requirements

When state estimation is run on a network with closed bus-bus switches, measurements associated with each connected bus must retain their per-bus meaning. In particular, measurements at one bus must not be treated as measurements at an undifferentiated merged location in a way that changes the estimated injections on the connected buses.
