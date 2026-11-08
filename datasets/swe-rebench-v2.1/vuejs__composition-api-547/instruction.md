Bug props in composition-api beta 14
```
export default {
  props: {
    filter: {
      type: Object,
      default: function() {
        return {
          c1: 'c1',
        }
      },
    },
  },
  setup(props) {
    console.log('props is: ', isRef(props), isReactive(props))
    watch(props, () => {  // error
      console.log(props)
    }
  }
}
```
beta11:  props is: false true
beta14:  props is: false false //  watch --> error
