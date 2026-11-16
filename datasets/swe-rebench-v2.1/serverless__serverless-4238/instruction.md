Separate Event for Alexa Smart Home Skill Trigger
# This is a Feature Proposal

## Description
AWS offers a separate trigger called 'Alexa Smart Home' for their Smart Home skills, besides the regular 'Alexa Skills Kit' trigger. As these both work in different ways, Serverless's current 'alexaSkill' event does not work for Smart Home skills. Adding a separate event type for this trigger allows the Serverless framework to work for Smart Home skills, which it currently doesn't.

Similar or dependent issues:
* #1409

## Additional Data
Serverless Framework Version: latest

### Additional contract requirements

AWS Lambda functions must support configuring Alexa Smart Home skills with a distinct `alexaSmartHome` event type. The event value accepts the skill application ID as a string.
