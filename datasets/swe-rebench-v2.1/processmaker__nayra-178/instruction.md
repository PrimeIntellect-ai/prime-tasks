Add BpmnElement reference
As a developer I would like to get the reference to the BPMN element of a loaded BPMN document, so I can work with that element reference.

```
interface EntityInterface
{

    /**
     * @return \ProcessMaker\Nayra\Contracts\Storage\BpmnElementInterface
     */
    public function getBpmnElement();

    /**
     * Set DOM element of this object.
     *
     * @param BpmnElementInterface $domElement
     *
     * @return $this
     */
    public function setBpmnElement(BpmnElementInterface $ownerDocument);
}
```
