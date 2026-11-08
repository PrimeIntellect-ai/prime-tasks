Gexf export sets the rgba's alpha-value to "None" if missing (gexf schema version 1.1 import)
### Current Behavior
Given I import a gexf-file which has schema version 1.1. There are only rgb values used for color definitions, for example:
`
      <node id="1789" label="1789">
        <ns0:color b="41" g="255" r="0" />...
`

When I export the graph imported before into a gexf file again using networkx (using nx.write_gexf and with default gexf-version '1.2draft') it adds alpha value "None":
`
      <node id="1789" label="1789">
        <viz:color r="0" g="255" b="41" a="None" />...
`

### Expected Behavior
In my opinion it would make more sense to use a default value of _a="1.0"_ to remain compatibility. For example Gephi 0.10.1 can not handle _alpha="None"_ values.

### Steps to Reproduce
You can download the dataset [Schoolday](https://www.michihenninger.ch/youtube/schoolday.gexf) and execute the following code:
`schoolday_graph = nx.read_gexf("data/schoolday.gexf")`
`nx.write_gexf(schoolday_graph, path="data/schoolday_new.gexf")`

Open the saved _schoolday_new.gexf_ file with a text editor. You can see that it uses schema version 1.2 and has every alpha value set to None.

### Current workaround:
The current workaround I use is to read and write the gexf-file in networkx like described in the reproduce section. Then I open the file with a text editor and replace all _a="None" by _a="1.0"_.

### Environment
Python version: 3.9.16
NetworkX version: 3.0
Gephi: 0.10.1
