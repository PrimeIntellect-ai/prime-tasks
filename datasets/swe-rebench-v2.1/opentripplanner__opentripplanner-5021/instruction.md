Incorrect precedence rules for NeTEx flexible line booking information
When flexible line booking information is added both at the ServiceJourney level (with FlexibleServiceProperties) and at the StopPoinInJourneyPattern level (with BookingArrangements), the booking information at StopPoinInJourneyPattern level has precedence and overrides the booking information at ServiceJourney level (See Nordic NeTEx Profile)
With the current implementation, OTP overrides all properties, including those that are not set at the lowest level.
For compliance with the Nordic NeTEx Profile, only the properties defined at the lowest level should be overriden.
OTP should merge the properties found at the 3 levels (Line, ServiceJourney, StopPoint) and apply precedence rules for the properties that are defined at multiple levels.

Given the following NeTEx :
```

<StopPointInJourneyPattern order="2" version="0" id="ENT:StopPointInJourneyPattern:cedd9330-895f-5b94-b49a-58eed604ad42">
                  <ScheduledStopPointRef ref="ENT:ScheduledStopPoint:0d023937-f8fc-5f17-ba70-39735a7554d6"/>
                  <ForAlighting>true</ForAlighting>
                  <ForBoarding>false</ForBoarding>
                  <BookingArrangements>
                    <BookingContact>
                      <Email>email</Email>
                      <Phone>phone number</Phone>
                      <Url>https://url</Url>
                    </BookingContact>
                  </BookingArrangements>
                </StopPointInJourneyPattern>

<ServiceJourney version="1" id="ENT:ServiceJourney:d56b012b-bd77-5d55-bf8a-9213a93f29eb">
              <Name>xxx</Name>
              <dayTypes>
                <DayTypeRef ref="ENT:DayType:97569f8d-dc6d-53b9-aff7-2cce008114d3"/>
              </dayTypes>
              <JourneyPatternRef ref="ENT:JourneyPattern:9902b3a9-e602-5fa3-bcbf-d3de837483c7" version="0"/>
              <passingTimes>
                <TimetabledPassingTime version="1" id="ENT:TimetabledPassingTime:510de245-53b8-51ef-a4ee-56771b0071b4">
                  <StopPointInJourneyPatternRef ref="ENT:StopPointInJourneyPattern:b0459ea4-a5b4-5979-a317-3279b382a7be" version="1"/>
                  <DepartureTime>07:00:00</DepartureTime>
                </TimetabledPassingTime>
                <TimetabledPassingTime version="0" id="ENT:TimetabledPassingTime:3097166b-d7af-5846-801d-7b85555e2b11">
                  <StopPointInJourneyPatternRef ref="ENT:StopPointInJourneyPattern:cedd9330-895f-5b94-b49a-58eed604ad42" version="0"/>
                  <LatestArrivalTime>08:00:00</LatestArrivalTime>
                  <EarliestDepartureTime>07:00:00</EarliestDepartureTime>
                </TimetabledPassingTime>
              </passingTimes>
              <FlexibleServiceProperties version="1" id="ENT:FlexibleServiceProperties:22">
                <BookingMethods>online callOffice</BookingMethods>
                <BookingAccess>public</BookingAccess>
                <BookWhen>advanceAndDayOfTravel</BookWhen>
                <BuyWhen>beforeBoarding</BuyWhen>
                <LatestBookingTime>19:00:00</LatestBookingTime>
                <BookingNote>xxxx</BookingNote>
              </FlexibleServiceProperties>
</ServiceJourney>
```

##  Expected behavior:
BookingInfo for the given stop should contain fields from both the `<BookingArrangements> `block and the `<FlexibleServiceProperties>` blocks.

##  Observed behavior:
BookingInfo contains only the fields from the` <BookingArrangements>` block.

## Version of OTP used (exact commit hash or JAR name)
dev-2.x
