State estimation module error when net has disabled branches
Hi, i came across a bug in the state estimation module, when I run the following code for the new functionality for trafo3w added in 5234059ca65a6c8e1bdb27ddbbd57cceb620a960 . The net was modified with one disabled line. The reason seems to be that,  the branch mapping from pp to ppci will change if some branches were disabled or connected between two disabled buses.

```
import pandapower as pp
from pandapower.estimation import estimate

net = pp.create_empty_network()

bus_slack = pp.create_bus(net, vn_kv=110)
pp.create_ext_grid(net, bus=bus_slack)

bus_20_1 = pp.create_bus(net, vn_kv=20,name="b")
pp.create_sgen(net, bus=bus_20_1, p_mw=0.03, q_mvar=0.02)

bus_10_1 = pp.create_bus(net, vn_kv=10)
pp.create_sgen(net, bus=bus_10_1, p_mw=0.02, q_mvar=0.02)

bus_10_2 = pp.create_bus(net, vn_kv=10)
pp.create_load(net, bus=bus_10_2, p_mw=0.06, q_mvar=0.01)
pp.create_line(net, from_bus=bus_10_1, to_bus=bus_10_2, std_type="149-AL1/24-ST1A 10.0", length_km=2)
disabled_line = pp.create_line(net, from_bus=bus_10_1, to_bus=bus_10_2, std_type="149-AL1/24-ST1A 10.0", length_km=2)
net.line.at[disabled_line, 'in_service'] = False

pp.create_transformer3w(net, bus_slack, bus_20_1, bus_10_1, std_type="63/25/38 MVA 110/20/10 kV")

pp.runpp(net)

pp.create_measurement(net, "p", "line", net.res_line.p_from_mw[0], 0.001, 0, 'from')
pp.create_measurement(net, "q", "line", net.res_line.q_from_mvar[0], 0.001, 0, 'from')
pp.create_measurement(net, "p", "line", net.res_line.p_to_mw[0], 0.001, 0, 'to')
pp.create_measurement(net, "q", "line", net.res_line.q_to_mvar[0], 0.001, 0, 'to')

pp.create_measurement(net, "p", "trafo3w", net.res_trafo3w.p_hv_mw[0], 0.001, 0, 'hv')
pp.create_measurement(net, "q", "trafo3w", net.res_trafo3w.q_hv_mvar[0], 0.001, 0, 'hv')
pp.create_measurement(net, "p", "trafo3w", net.res_trafo3w.p_mv_mw[0], 0.002, 0, 'mv')
pp.create_measurement(net, "q", "trafo3w", net.res_trafo3w.q_mv_mvar[0], 0.002, 0, 'mv')
pp.create_measurement(net, "p", "trafo3w", net.res_trafo3w.p_lv_mw[0], 0.001, 0, 'lv')
pp.create_measurement(net, "q", "trafo3w", net.res_trafo3w.q_lv_mvar[0], 0.001, 0, 'lv')

pp.create_measurement(net, "v", "bus", net.res_bus.vm_pu[0], 0.01, 0)
pp.create_measurement(net, "v", "bus", net.res_bus.vm_pu[1], 0.01, 1)

success = estimate(net)
```

### Additional contract requirements

State estimation must complete successfully and produce bus voltage estimates consistent with a successful power flow when branches are omitted because they are out of service or because an endpoint bus is out of service. This must remain true for measurements on active branches in a network that includes a three-winding transformer.
