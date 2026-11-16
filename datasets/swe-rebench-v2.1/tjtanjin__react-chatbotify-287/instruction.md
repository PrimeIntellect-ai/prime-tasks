[Task] Add unit test cases for VoiceButton component
**Task Description:**
Currently, we run unit tests using jest which can be found [**here**](https://github.com/tjtanjin/react-chatbotify/tree/main/__tests__).

However, the test cases are not yet comprehensive enough and work can be done to cover more grounds. Specifically for this issue, we hope to add test cases for the `VoiceButton` component.

**Deliverable(s):**
New unit test cases that cover the testing of the `VoiceButton` component.

**Additional Context:**
- Button components can be found [**here**](https://github.com/tjtanjin/react-chatbotify/tree/main/src/components/Buttons)
- An example for `AudioButton` can be found [**here**](https://github.com/tjtanjin/react-chatbotify/blob/main/__tests__/components/AudioButton.test.tsx) which may serve as a good source for reference

### Additional contract requirements

- The VoiceButton icon must render with `data-testid="rcb-voice-icon"`.
