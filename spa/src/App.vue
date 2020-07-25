<template>
  <div id="app">
    <amplify-authenticator username-alias="email">
      <div>Response: {{ apiResponse }}</div>
      <amplify-sign-out />
        <amplify-sign-up slot="sign-up" username-alias="email" :form-fields.prop="formFields" />
    </amplify-authenticator>

  </div>
</template>

<script>

export default {
  name: 'App',
  components: {
  },
  data() {
    return {
      apiResponse: '',
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
  mounted() {
    const myInit = {
      body: { name: "world" }
    }
    this.$API.post('hello', '', myInit).
      then(response => {
        console.log(response.result)
        this.apiResponse = response.result
      })
      .catch(error => {
        console.log("error", error.response)
      })
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
