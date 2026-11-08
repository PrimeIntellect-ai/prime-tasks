Adjust no-bpmndi rule to also catch messageFlows without visual representation
__Is your feature request related to a problem? Please describe__

The current implementation of the no-bpmndi rule seems to not catch the case where visual representation of a messageFlow is missing. Example:

```
<?xml version="1.0" encoding="UTF-8"?>
<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" xmlns:di="http://www.omg.org/spec/DD/20100524/DI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:modeler="http://camunda.org/schema/modeler/1.0" xmlns:camunda="http://camunda.org/schema/1.0/bpmn" id="Definitions_0o87biy" targetNamespace="http://bpmn.io/schema/bpmn" exporter="Camunda Modeler" exporterVersion="5.0.0" modeler:executionPlatform="Camunda Cloud" modeler:executionPlatformVersion="8.0.0" camunda:diagramRelationId="c3dfa14f-62b5-469a-99c2-eea2474361c4">
  <bpmn:collaboration id="Collaboration_03svvle">
    <bpmn:participant id="Participant_19296tk" name="Camunda" processRef="optimizeRelease" />
    <bpmn:messageFlow id="Flow_02zjpio" />
    <bpmn:messageFlow id="Flow_02fgw1s" />
    <bpmn:messageFlow id="Flow_1tfrum1" />
    <bpmn:messageFlow id="Flow_0j117b6" />
    <bpmn:messageFlow id="Flow_1p82kq7" />
    <bpmn:messageFlow id="Flow_12ujv1h" />
    <bpmn:messageFlow id="Flow_1ud5vc7" />
    <bpmn:messageFlow id="Flow_1pgfh6h" />
    <bpmn:messageFlow id="Flow_1n7tpee" />
  </bpmn:collaboration>
  <bpmn:process id="optimizeRelease" name="Optimize Release Process" isExecutable="true">
    <bpmn:laneSet id="LaneSet_0vxjmiv">
      <bpmn:lane id="other-lane" name="Other">
        <bpmn:flowNodeRef>Event_14w2go1</bpmn:flowNodeRef>
      </bpmn:lane>
      <bpmn:lane id="product-manager-lane" name="Product Manager">
        <bpmn:flowNodeRef>Event_14w2go1</bpmn:flowNodeRef>
        <bpmn:flowNodeRef>Start_1</bpmn:flowNodeRef>
        <bpmn:flowNodeRef>Event_14a4ede</bpmn:flowNodeRef>
        <bpmn:flowNodeRef>add-cat-pic</bpmn:flowNodeRef>
      </bpmn:lane>
    </bpmn:laneSet>
    <bpmn:endEvent id="Event_14w2go1" />
    <bpmn:sequenceFlow id="Flow_1yoohwu" sourceRef="Start_1" targetRef="add-cat-pic" />
    <bpmn:startEvent id="Start_1" name="At beginning of release month">
      <bpmn:outgoing>Flow_1yoohwu</bpmn:outgoing>
    </bpmn:startEvent>
    <bpmn:endEvent id="Event_14a4ede">
      <bpmn:incoming>Flow_1opo8o2</bpmn:incoming>
    </bpmn:endEvent>
    <bpmn:sequenceFlow id="Flow_1opo8o2" sourceRef="add-cat-pic" targetRef="Event_14a4ede" />
    <bpmn:serviceTask id="add-cat-pic" name="Add cat pic of the month">
      <bpmn:incoming>Flow_1yoohwu</bpmn:incoming>
      <bpmn:outgoing>Flow_1opo8o2</bpmn:outgoing>
    </bpmn:serviceTask>
    <bpmn:textAnnotation id="TextAnnotation_1m4hg8y">
      <bpmn:text>Configure timer cycle</bpmn:text>
    </bpmn:textAnnotation>
    <bpmn:association id="Association_1srpwa7" sourceRef="Start_1" targetRef="TextAnnotation_1m4hg8y" />
  </bpmn:process>
  <bpmndi:BPMNDiagram id="BPMNDiagram_1">
    <bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="Collaboration_03svvle">
      <bpmndi:BPMNShape id="Participant_19296tk_di" bpmnElement="Participant_19296tk" isHorizontal="true">
        <dc:Bounds x="175" y="45" width="4310" height="1085" />
        <bpmndi:BPMNLabel />
      </bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="Lane_1hg66tj_di" bpmnElement="product-manager-lane" isHorizontal="true">
        <dc:Bounds x="205" y="497.5" width="4280" height="632.5" />
        <bpmndi:BPMNLabel />
      </bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="Lane_1i9ntug_di" bpmnElement="other-lane" isHorizontal="true">
        <dc:Bounds x="205" y="45" width="4280" height="452.5" />
        <bpmndi:BPMNLabel />
      </bpmndi:BPMNShape>
      <bpmndi:BPMNEdge id="Flow_1opo8o2_di" bpmnElement="Flow_1opo8o2">
        <di:waypoint x="495" y="625" />
        <di:waypoint x="622" y="625" />
      </bpmndi:BPMNEdge>
      <bpmndi:BPMNEdge id="Flow_1yoohwu_di" bpmnElement="Flow_1yoohwu">
        <di:waypoint x="273" y="625" />
        <di:waypoint x="395" y="625" />
      </bpmndi:BPMNEdge>
      <bpmndi:BPMNShape id="Event_14w2go1_di" bpmnElement="Event_14w2go1">
        <dc:Bounds x="4412" y="477" width="36" height="36" />
        <bpmndi:BPMNLabel>
          <dc:Bounds x="4375" y="520" width="71" height="14" />
        </bpmndi:BPMNLabel>
      </bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="Event_06qyu4n_di" bpmnElement="Start_1">
        <dc:Bounds x="237" y="607" width="36" height="36" />
        <bpmndi:BPMNLabel>
          <dc:Bounds x="219" y="650" width="74" height="27" />
        </bpmndi:BPMNLabel>
      </bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="Event_14a4ede_di" bpmnElement="Event_14a4ede">
        <dc:Bounds x="622" y="607" width="36" height="36" />
      </bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="Activity_1gbnx01_di" bpmnElement="add-cat-pic">
        <dc:Bounds x="395" y="585" width="100" height="80" />
      </bpmndi:BPMNShape>
      <bpmndi:BPMNShape id="TextAnnotation_1m4hg8y_di" bpmnElement="TextAnnotation_1m4hg8y">
        <dc:Bounds x="225" y="525" width="100" height="39" />
        <bpmndi:BPMNLabel />
      </bpmndi:BPMNShape>
      <bpmndi:BPMNEdge id="Association_1srpwa7_di" bpmnElement="Association_1srpwa7">
        <di:waypoint x="259" y="608" />
        <di:waypoint x="269" y="564" />
      </bpmndi:BPMNEdge>
    </bpmndi:BPMNPlane>
  </bpmndi:BPMNDiagram>
</bpmn:definitions>
```



__Describe the solution you'd like__

no-bpmndi rule should error also for messageFlows without visual representation


__Describe alternatives you've considered__

seperate new rule


__Additional context__

<!-- Add any other context or screenshots about the feature request here. -->
