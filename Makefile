lambdas:
	cd ./lambdas/hello/ && GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o ./main
	cd ./lambdas/sqs-consumer/ && GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o ./main
	cd ./lambdas/dlq-consumer/ && GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o ./main

plan:
	cd ./terraform && terraform plan
apply:
	cd ./terraform && terraform apply

destroy:
	cd ./terraform && terraform destroy

spaconfig:
	terraform output -json -state ./terraform/terraform.tfstate | go run ./parser/terraform-to-spa-config/main.go > ./spa/src/terraform-exports.js
	terraform output -json -state ./terraform/terraform.tfstate | go run ./parser/terraform-to-endpoints/main.go > ./spa/src/endpoints.js

taint:
	cd ./terraform && terraform taint aws_api_gateway_deployment.hello_deploy

.PHONY: lambdas plan apply destroy spaconfig taint
