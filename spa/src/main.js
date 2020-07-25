import Vue from 'vue'
import App from './App.vue'
//import router from './router'
import Amplify, { API, Auth } from 'aws-amplify'
import '@aws-amplify/ui-vue'
import awsconfig from './terraform-exports'
import { endpoints } from './endpoints'

Amplify.configure(awsconfig)
Amplify.configure({API: { endpoints }})

Vue.prototype.$API = API
Vue.prototype.$Auth = Auth

Vue.config.productionTip = false
new Vue({
  render: h => h(App),
}).$mount('#app')
