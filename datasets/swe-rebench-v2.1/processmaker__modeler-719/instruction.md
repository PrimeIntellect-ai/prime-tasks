Advanced Accordion always last
The advanced accordion should always be the last accordion in the inspector panel:

<img width="284" alt="Screen Shot 2019-09-30 at 11 18 43 AM" src="https://user-images.githubusercontent.com/7561061/65892326-146e5f80-e374-11e9-8cb0-b4f8bac53849.png">

In some cases, the advanced accordion does not appear last, like for the task component:
<img width="291" alt="Screen Shot 2019-09-30 at 11 19 20 AM" src="https://user-images.githubusercontent.com/7561061/65892392-37990f00-e374-11e9-8a2c-0fdab0704184.png">

This occurs because calls to `registerInspectorExtension` does not maintain the order of the inspector accordions.

### Additional contract requirements

- Expose the registration operation as a public function from `src/components/InspectorExtensionManager.js` (importable as `@/components/InspectorExtensionManager`).
- `node` is an object with an `inspectorConfig` array; its first element holds the inspector accordion containers and their `items` arrays.
- `config` describes an accordion to register. When `config.container` is present, the configuration is registered in the node's top-level inspector items (`node.inspectorConfig[0].items`); when `config.container` is absent, it is registered in the items of the node's first inspector container (`node.inspectorConfig[0].items[0].items`).
- When `config.id` matches the `id` of an existing item in the target items list, that existing item is replaced; otherwise the configuration is added to the list.
- Any accordion whose `name` is `'advanced'` is positioned as the last item of the list it is registered in.
- The function returns no value.
