$: {} throwing an error
**Describe the bug**
A clear and concise description of what the bug is.
I am getting an error while I was trying  to use $:{}. Here is my component code.
```javascript
export default function Contact(props) {
    let $name = "Zafar Ansari"
    let $message = ""

    $: {
        $message = "My name is " + $name
    }
    return (
        <>
            <input value={$name} />
            <p>{$message}</p>
         </>
    )
}
```


**Expected behavior**
$:{} should not throw an error

**Screenshots**
![image](https://github.com/Rezact/Rezact/assets/5788284/e2222918-3a79-432a-bcdc-9827bacff9c5)

**Desktop (please complete the following information):**
 - Ubuntu
 - Browser Microsoft Edge

### Additional contract requirements

- In the reactive-computation example, expose an input with id `issue-22-input` and initial value `Zafar Ansari`, and elements with ids `issue-22-test` and `issue-22-test2`. Initially, their text content must be `My name is Zafar Ansari` and `Zafar Ansari is my name`, respectively. Typing `Zafar` into the input must update its value to `Zafar AnsariZafar` and update the two text contents to `My name is Zafar AnsariZafar` and `Zafar AnsariZafar is my name`, respectively.
