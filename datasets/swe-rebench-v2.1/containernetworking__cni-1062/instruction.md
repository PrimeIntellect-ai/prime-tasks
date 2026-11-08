Add Table ID in CNI Result and Attribute
Using Source Based Routing and VRF meta plugins, routes are configured in different tables that are not represented in the result.

In a chained CNI configuration, the first main cni will create the requested routes and currently, VRF and SBR plugins are moving some of those routes to newly created routing table(s). Adding the `Table` property in the Result would help with the clarity of what and how networks are being configured.

Routes could be configured in a specific table by the "main" CNI in the chain, and the SBR plugin could just create the policy route towards this table without moving any route. The current behavior could be also kept, the SBR and VRF plugin would have to modify the result to specify in which table routes have been moved.

Adding the option to pass the table number is described as future enhancement in the SBR plugin documentation: https://www.cni.dev/plugins/current/meta/sbr/#future-enhancements-and-known-limitations
Here is what would be the changes in the SBR plugin with the table ID without moving routes: https://github.com/LionelJouin/plugins/commit/098774320801f8e0ccc04240771cbb382937ce65

### Additional contract requirements

- The `pkg/types.Route` struct must expose a `Table *int` field.
- For the tested route with table 50, `Route.String()` must return `{Dst:{IP:1.2.3.0 Mask:ffffff00} GW:1.2.3.1 MTU:1500 AdvMSS:1340 Priority:100 Table:50}`.
