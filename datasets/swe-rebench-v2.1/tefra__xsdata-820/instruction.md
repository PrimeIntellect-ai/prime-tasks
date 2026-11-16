When a schema overrides attributes (with use="required") this is not reflected in the output
Considering the example below.

```
	<xsd:element name="TimeDemandTypeAssignment" abstract="false" substitutionGroup="Assignment_">
		<xsd:annotation>
			<xsd:documentation>The assignment of a TIME DEMAND TYPE to a TIME BAND depending on the DAY TYPE and GROUP OF TIMING LINKS.</xsd:documentation>
		</xsd:annotation>
		<xsd:complexType>
			<xsd:complexContent>
				<xsd:restriction base="TimeDemandTypeAssignment_VersionStructure">
					<xsd:sequence>
						<xsd:sequence>
							<xsd:sequence>
								<xsd:group ref="EntityInVersionGroup" minOccurs="0"/>
							</xsd:sequence>
							<xsd:sequence>
								<xsd:group ref="DataManagedObjectGroup"/>
							</xsd:sequence>
							<xsd:sequence>
								<xsd:group ref="AssignmentGroup"/>
							</xsd:sequence>
						</xsd:sequence>
						<xsd:sequence>
							<xsd:group ref="TimeDemandTypeAssignmentGroup"/>
						</xsd:sequence>
					</xsd:sequence>
					<xsd:attribute name="id" type="TimeDemandTypeAssignmentIdType" use="required"/>
				</xsd:restriction>
			</xsd:complexContent>
		</xsd:complexType>
	</xsd:element>
```

Which ultimately resolves to:
```
        <xsd:complexType name="EntityStructure" abstract="true">
                <xsd:annotation>
                        <xsd:documentation>Type for ENTITY.</xsd:documentation>
                </xsd:annotation>
                <xsd:attribute name="nameOfClass" type="NameOfClass" use="optional">
                        <xsd:annotation>
                                <xsd:documentation>Name of Class of the ENTITY. Allows reflection. Fixed for each ENTITY type.</xsd:documentation>
                        </xsd:annotation>
                </xsd:attribute>
                <xsd:attribute name="id" type="ObjectIdType" use="optional">
                        <xsd:annotation>
                                <xsd:documentation>Identifier of ENTITY.</xsd:documentation>
                        </xsd:annotation>
                </xsd:attribute>
        </xsd:complexType>
```

What I notice is that the use="required" is never overriden.
```
<xsd:attribute name="id" type="TimeDemandTypeAssignmentIdType" use="required"/>
```

What I would like to see happening is overriding the field in the class that does not inherits its (ultimate) parents properties.
```
@dataclass(unsafe_hash=True)
class TimeDemandTypeAssignmentVersionStructure(AssignmentVersionStructure1):
    """
    Type for TIME DEMAND TYPE ASSIGNMENT.
    """
    class Meta:
        name = "TimeDemandTypeAssignment_VersionStructure"

    time_demand_type_ref: Optional[TimeDemandTypeRef] = field(
        default=None,
        metadata={
            "name": "TimeDemandTypeRef",
            "type": "Element",
            "namespace": "http://www.netex.org.uk/netex",
        }
    )
    timeband_ref: Optional[TimebandRef] = field(
        default=None,
        metadata={
            "name": "TimebandRef",
            "type": "Element",
            "namespace": "http://www.netex.org.uk/netex",
        }
    )
    group_of_timing_links_ref: Optional[GroupOfTimingLinksRef] = field(
        default=None,
        metadata={
            "name": "GroupOfTimingLinksRef",
            "type": "Element",
            "namespace": "http://www.netex.org.uk/netex",
        }
    )
   # The current generation does not add this:
    id: str = field(
         default=None,
         metadata={
             "type": "Attribute",
         }
    )
```

### Additional contract requirements

- The overridden attribute must be emitted in the derived class (the class that does not inherit its ultimate parent's properties) instead of only being inherited from the parent.
- The emitted field must preserve the override's required occurrence: `min_occurs == 1` and `max_occurs == 1`, which the generator renders as `"required": True` in the field metadata.
