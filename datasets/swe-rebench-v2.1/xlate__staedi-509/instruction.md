MinLength not triggering validation failure
When using composites in EDIFACT, the MinLength value does not seem to work

Schema extract:

	<segmentType name="LOC">
		<sequence>
			<element type="E3227" minOccurs="0" maxOccurs="1"/>
			<composite type="C517" minOccurs="1" maxOccurs="1"/>
			<composite type="C519" minOccurs="0" maxOccurs="1"/>
			<composite type="C553" minOccurs="0"/>
			<element type="E5479" minOccurs="0"/>
		</sequence>
	</segmentType>

	<elementType name="E3225" base="string" minLength="5" maxLength="17"/>

	<compositeType name="C517">
		<sequence>
			<element type="E3225" minOccurs="1" maxOccurs="1"/>
			<element type="E1131" minOccurs="0"/>
			<element type="E3055" minOccurs="0" maxOccurs="1"/>
			<element type="E3224" minOccurs="0"/>
		</sequence>
	</compositeType>

So you can see the LOC segment contains a C517 composite, which begins with an E3225 element, with a minOccurs of 1

I would expect to see a failure if the E3225 element is missing but the E3055 element is populated as follows:

`LOC+172+::92'`

as opposed to the valid format:

`LOC+172+VWXYZ::92'`

### Additional contract requirements

- For the described missing-component case, report exactly one validation error: `EDIStreamValidationError.REQUIRED_DATA_ELEMENT_MISSING`, at segment `LOC`, segment position 6, element position 2, component position 1.
