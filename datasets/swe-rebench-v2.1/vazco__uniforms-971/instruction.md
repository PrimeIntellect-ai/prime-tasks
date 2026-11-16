uniforms-antd. SelectField. Typing improvements to provide access to antd native props
Motivation:
Ability to pass native antd props like "showSearch", "optionFilterProp", and others.
It already works. As far as I understand via filterDOMProps. But there are some issues with types.

Solution:
I suppose the root issue is of using Omit on the union as Omit looks in such a case only on the intersection of props. I attached a solution that works.

Please have a look. If it makes sense for you, I'll create a PR

![image](https://user-images.githubusercontent.com/3891411/117450975-965c3c80-af4a-11eb-8a20-8f41509fd296.png)

### Additional contract requirements

Callers can pass native antd Select props, including `showSearch` and `optionFilterProp`, to `uniforms-antd`'s `SelectField` without TypeScript rejecting them.
