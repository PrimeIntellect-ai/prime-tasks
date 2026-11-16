Textfield type="password" not working for antd style
The `'uniforms-antd/TextField` does not properly pass the `type` prop. See below.

For demonstration, I imported both antd and unstyled versions. The antd does not mask the input field as expected.

```jsx
import AutoForm from 'uniforms-antd/AutoForm';
import TextField from 'uniforms-antd/TextField';
import TextField2 from 'uniforms-unstyled/TextField';

<AutoForm schema={loginFormSchema} onSubmit={submitLogin}>
 <TextField name="email" />
 <TextField name="password" type="password" />
 <TextField2 name="password" type="password" />
 <SubmitField>Submit</SubmitField>
</AutoForm>
```
![2017-09-11 10 40 16](https://user-images.githubusercontent.com/136654/30280410-aa704754-96dd-11e7-8bd2-f68494630c6b.gif)
