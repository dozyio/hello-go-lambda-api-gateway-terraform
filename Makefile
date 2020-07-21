all:
	GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o main . && rm hello.zip && zip hello.zip main
deploy:
	terraform apply -auto-approve
