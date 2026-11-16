Comparative adjectives in Russian dictionary
It has been detected that, in some Russian dictionary entries, the comparative degree is not being extracted correctly from Wiktionary. Two representative examples are detailed below, as the rest of the checked adjectives present the information correctly:

- In the word “опасный”, the form of the comparative degree corresponds to a number, while in Wiktionary the following appears "Прилагательное, качественнное, тип склонения по классификациии А. Зализняка - 1*a. Сравнительная степепень - опа́снеее, опа́сней.", so I understand that it is not correctly extracted.

![Image](https://github.com/user-attachments/assets/db2cd237-1ca0-4943-a611-82f5d46eb718)

- In the word “смелый” the comparative form does not even exist, while in Wiktionary the following appears "Прилагагательное, качественнное, тип склонения по класссификациии А. Зализняка - 1a/c'. Сравнительная степепень - смеле́е, смелеле́й, посмелеле́е, посмеле́й.", so I understand that it was not extracted correctly.

### Additional contract requirements

For опасный, the comparative forms shown by the expanded Wiktionary entry are опа́снее and опа́сней; опа́снеее in the descriptive text is a typo. Extract both as comparative forms. Preserve extraction of the perfective form specified by the `соотв` parameter in Russian verb templates.
