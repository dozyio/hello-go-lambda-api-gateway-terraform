package main

import (
    "encoding/json"
    "fmt"
    "net/http"
    "os"
    "context"
    "github.com/aws/aws-lambda-go/events"
    runtime "github.com/aws/aws-lambda-go/lambda"
)
type MyEvent struct {
    Name string `json:"name"`
}
func handleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
    value := MyEvent{
        Name: "",
    }
    err := json.Unmarshal([]byte(request.Body), &value)
    if err != nil {
        fmt.Fprintf(os.Stdout, "Unmarshal error")
        return events.APIGatewayProxyResponse{
            StatusCode: http.StatusBadRequest,
            Body: "",
            IsBase64Encoded: false,
        }, nil
    }

    name := value.Name
    if name == "" {
        fmt.Fprintf(os.Stdout, "Name not specified")
        return events.APIGatewayProxyResponse{
            StatusCode: http.StatusBadRequest,
            Body: "Name not specified",
            IsBase64Encoded: false,
        }, nil
    }

    res := fmt.Sprintf("Hello %s", name)
    return events.APIGatewayProxyResponse{
        StatusCode: http.StatusOK,
        Body: "{ 'Result': '"+res+"' }",
        IsBase64Encoded: false,
    }, nil
}
func main() {
    runtime.Start(handleRequest)
}
