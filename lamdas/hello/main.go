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
    //cors
    headers := map[string]string{
        "Access-Control-Allow-Origin":  "*",
        "Access-Control-Allow-Methods": "OPTIONS,POST",
        "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
    }

    value := MyEvent{
        Name: "",
    }
    err := json.Unmarshal([]byte(request.Body), &value)
    if err != nil {
        fmt.Fprintf(os.Stdout, "Unmarshal error")
        return events.APIGatewayProxyResponse{
            StatusCode: http.StatusBadRequest,
            Headers: headers,
            Body: "",
            IsBase64Encoded: false,
        }, nil
    }

    name := value.Name
    if name == "" {
        fmt.Fprintf(os.Stdout, "Name not specified")
        return events.APIGatewayProxyResponse{
            StatusCode: http.StatusBadRequest,
            Headers: headers,
            Body: "Name not specified",
            IsBase64Encoded: false,
        }, nil
    }

    res := fmt.Sprintf("Hello %s", name)
    return events.APIGatewayProxyResponse{
        StatusCode: http.StatusOK,
        Headers: headers,
        Body: "{ \"result\": \""+res+"\" }",
        IsBase64Encoded: false,
    }, nil
}
func main() {
    runtime.Start(handleRequest)
}
