Plans on Cost Explorer's get_cost_and_usage
Hello! I am aware Cost Explorer is available now in moto, but only for [certain features](http://docs.getmoto.org/en/latest/docs/services/ce.html?highlight=cost%20explorer#moto.ce.models.CostExplorerBackend).
So, I have a quick question, are there any plans on mocking Cost Explorer's **get_cost_and_usage**?

### Additional contract requirements

Moto should support calling Cost Explorer's `get_cost_and_usage` operation. A valid request must receive a successful response containing `ResultsByTime` and `DimensionValueAttributes` collections.
