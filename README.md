# Hello Microservice - using AWS, Terraform and Vue.js

Example hello microservice using a Go AWS Lambda, API Gateway with CORS and AWS Cognito for authentication - deployed using Terraform.
Also includes a sample Vue.js SPA frontend using AWS amplify auth and api to consume the REST hello service. SPA configured via Terraform output.

# Setup
```sh
cd terraform && terraform init
```

# Build
```sh
make lamdas
cd spa && npm install
```

# Deploy
```sh
make deploy
make genconfig
```

# Run test SPA locally
```sh
cd spa && npm run serve
```

# Redeploy api gateway
The api gateway sometimes needs redeploying (i.e. when changing auth or CORS settings). In this case you'll need to taint the terraform state with the following and redeploy.

```sh
make taint
make deploy
```

