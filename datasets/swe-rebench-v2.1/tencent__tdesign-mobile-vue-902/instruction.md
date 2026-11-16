[组件名称] 描述问题的标题
### tdesign-mobile-vue 版本

0.26.0

### 重现链接

https://tdesign.tencent.com/mobile-vue/components/form

### 重现步骤

个人简介的t-textarea组件v-model绑定了值，输入文字对应的计数器的值不正确，初始有值计数器值仍然为0

### 期望结果

计数器值和输入框内v-model绑定的文字长度一致

### 实际结果

计数器值和输入框内v-model绑定的文字长度不一致

### 框架版本

_No response_

### 浏览器版本

_No response_

### 系统版本

_No response_

### Node版本

15

### 补充说明

_No response_
[Form] t-textarea组件的计数不正确
### tdesign-mobile-vue 版本

0.26.0

### 重现链接

https://stackblitz.com/edit/zlysxy?file=src%2Fdemo.vue

### 重现步骤

Form组件中的textarea组件计数问题

1.  初始化的值不正确
<img width="542" alt="image" src="https://github.com/Tencent/tdesign-mobile-vue/assets/13745660/566a55f4-f1a7-463e-86ee-a42bcb972fe9">


2.  输入了值，数据差1
<img width="550" alt="image" src="https://github.com/Tencent/tdesign-mobile-vue/assets/13745660/ee07c941-80ae-4169-a3da-a186fc25e1e8">

<img width="533" alt="image" src="https://github.com/Tencent/tdesign-mobile-vue/assets/13745660/f59beeed-b0b7-4a7b-8a27-447ecf6886fb">


### 期望结果

正确的计数结果

### 实际结果

_No response_

### 框架版本

_No response_

### 浏览器版本

_No response_

### 系统版本

_No response_

### Node版本

_No response_

### 补充说明

_No response_
