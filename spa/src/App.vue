<template>
  <div id="app">
    <amplify-authenticator username-alias="email" v-if="authState !== 'signedin'">
        <amplify-sign-up slot="sign-up" username-alias="email" :form-fields.prop="formFields" />
    </amplify-authenticator>
    <div v-if="authState === 'signedin' && user">
      <div>User: {{ user.username }}</div>
      <div v-if="!error">API - Response: {{ apiResponse }} SQS: {{ apiSQS }}</div>
      <div v-if="error">{{ error }}</div>
      <amplify-sign-out />
    </div>
  </div>
</template>

<script>
import { onAuthUIStateChange } from '@aws-amplify/ui-components'

export default {
  name: 'App',
  components: {
  },
  data() {
    return {
      user: null,
      authState: null,
      apiResponse: 'Waiting...',
      apiSQS: 'Waiting...',
      error: null,
      formFields: [
        {
          type: 'email',
          label: 'Email Address',
          required: true,
        },
        {
          type: 'password',
          label: 'Password',
          required: true,
        },
      ]
    }
  },
  created() {
    onAuthUIStateChange((authState, authData) => {
      console.log('onAuthUIStateChange', authState, authData)
      const previousAuthState = this.authState
      this.authState = authState
      this.user = authData
      if(authState === 'signedin' && authData && previousAuthState != authState){
        this.callApi()
      }
    })
  },
  beforeDestroy() {
    return onAuthUIStateChange
  },
  methods: {
    callApi(){
      const body = {
        body: { name: this.user.attributes.email }
      }
      this.$API.post('hello', '', body).
        then(response => {
          this.apiResponse = response.result
          this.apiSQS = response.sqs
        })
        .catch(error => {
          this.error = error
          console.log("error: ", error)
        })
    },
  }
}
</script>

<style>
#app {
  font-family: Avenir, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  text-align: center;
  color: #2c3e50;
  margin-top: 60px;
}
</style>
