Electronic, aka Fermi-Dirac entropy
The paper https://www.mdpi.com/1099-4300/20/8/593 cites

![image](https://user-images.githubusercontent.com/19669089/198891377-4d7a890f-1b2b-467a-a442-e8883c57e4a2.png)

![image](https://user-images.githubusercontent.com/19669089/198891384-7aea8cf7-19dc-42d4-b5fe-e3fd3296f262.png)

This is actually called _electronic_ entropy in Wikipedia: https://en.wikipedia.org/wiki/Electronic_entropy

Seems like a straightforward new direct Entropy method to add.

### Additional contract requirements

Expose the direct measure under the public name `ElectronicEntropy`, so a caller can evaluate it with `information(ElectronicEntropy(), probs)`. For a discrete probability distribution, the result is the sum of its Shannon entropy and Shannon extropy.
