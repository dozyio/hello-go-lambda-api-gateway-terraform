import Vue from 'vue'
import App from './App.vue'
//import router from './router'
import Amplify, { API } from 'aws-amplify'
import '@aws-amplify/ui-vue'
import awsconfig from './terraform-exports'
import { endpoints } from './endpoints'

Amplify.configure(awsconfig)
Amplify.configure({API: { endpoints }})

Vue.prototype.$API = API

Vue.config.productionTip = false
new Vue({
  render: h => h(App),
}).$mount('#app')
