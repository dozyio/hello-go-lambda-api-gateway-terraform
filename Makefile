lamda:
	cd ./lamdas/hello/ && GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o ./main
deploy:
	cd ./terraform && terraform apply
genconfig:
	terraform output -json -state ./terraform/terraform.tfstate | go run ./parser/terraform-to-spa-config/main.go > ./spa/src/terraform-exports.js
	terraform output -json -state ./terraform/terraform.tfstate | go run ./parser/terraform-to-endpoints/main.go > ./spa/src/endpoints.js
taint:
	cd ./terraform && terraform taint aws_api_gateway_deployment.hello_deploy
