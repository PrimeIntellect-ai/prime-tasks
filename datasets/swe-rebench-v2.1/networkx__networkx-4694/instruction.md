Getting shape types from GraphML written by yEd
<!-- If you have a general question about NetworkX, please use the discussions tab to create a new discussion -->

<!--- Provide a general summary of the issue in the Title above -->


### Current Behavior
<!--- Tell us what happens instead of the expected behavior -->
I have a GraphML file, written by [yEd](https://www.yworks.com/products/yed). NetworkX reads it just fine with `read_graphml()`, however, one very important information is missing: the type of the nodes (eg. `diamond`, `roundrectangle` etc).

### Expected Behavior
<!--- Tell us what should happen -->
I would except to be able to get that information, because it's necessary for processing and understanding the exported graph.

### Steps to Reproduce
<!--- Provide a minimal example that reproduces the bug -->
Create a graph with [yEd](https://www.yworks.com/products/yed) with various shapes. Export it to GraphML and load it back with NetworkX's `read_graphml()`. The shape types are not there.

### Environment
<!--- Please provide details about your local environment -->
Python version: 3.8.5
NetworkX version: 2.5


### Additional context
<!--- Add any other context about the problem here, screenshots, etc. -->
yEd exports the shape type in the XML like this:
```XML
    <node id="n1">
      <data key="d5" xml:space="preserve"><![CDATA[lfx="red"
bela="2"]]></data>
      <data key="d6">
        <y:ShapeNode>
          <y:Geometry height="93.0" width="93.0" x="133.0" y="509.90625"/>
          <y:Fill color="#FFCC00" transparent="false"/>
          <y:BorderStyle color="#000000" raised="false" type="line" width="1.0"/>
          <y:NodeLabel alignment="center" autoSizePolicy="content" fontFamily="Dialog" fontSize="12" fontStyle="plain" hasBackgroundColor="false" hasLineColor="false" height="17.96875" horizontalTextPosition="center" iconTextGap="4" modelName="custom" textColor="#000000" verticalTextPosition="bottom" visible="true" width="29.16015625" x="31.919921875" xml:space="preserve" y="37.515625">RED
             <y:LabelModel><y:SmartNodeLabelModel distance="4.0"/></y:LabelModel>
             <y:ModelParameter>
               <y:SmartNodeLabelModelParameter labelRatioX="0.0" labelRatioY="0.0" nodeRatioX="0.0" nodeRatioY="0.0" offsetX="0.0" offsetY="0.0" upX="0.0" upY="-1.0"/>
             </y:ModelParameter>
          </y:NodeLabel>
          <y:Shape type="roundrectangle"/>
        </y:ShapeNode>
      </data>
    </node>
```

Reference: [yEd documentation](https://docs.yworks.com/graphml/schema-doc/http___www.yworks.com_xml_graphml/simpleType/shapeType.type.html)

### Additional contract requirements

- The node shape type is exposed as the node attribute `shape_type`, a string (for example `"rectangle"` or `"com.yworks.flowchart.terminator"`).
- The yEd node description is exposed as the node attribute `description`, a string that preserves the CDATA content including its newlines.
- The public function `parse_graphml(data, node_type=str, edge_key_type=int, force_multigraph=False)` in `networkx.readwrite.graphml` (also available as `nx.parse_graphml`) parses GraphML supplied as a string and exposes the same `shape_type` and `description` node attributes when present.
