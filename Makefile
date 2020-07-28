lambdas:
	cd ./lamdas/hello/ && rm -rf ./main && GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o ./main
	cd ./lamdas/sqs-consumer/ && rm -rf ./main && GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o ./main

plan:
	cd ./terraform && terraform plan
deploy:
	cd ./terraform && terraform apply

destroy:
	cd ./terraform && terraform destroy

spaconfig:
	terraform output -json -state ./terraform/terraform.tfstate | go run ./parser/terraform-to-spa-config/main.go > ./spa/src/terraform-exports.js
	terraform output -json -state ./terraform/terraform.tfstate | go run ./parser/terraform-to-endpoints/main.go > ./spa/src/endpoints.js

taint:
	cd ./terraform && terraform taint aws_api_gateway_deployment.hello_deploy
