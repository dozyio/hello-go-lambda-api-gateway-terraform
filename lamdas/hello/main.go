package main

import (
    "errors"
    "fmt"
    "net/http"
    "os"
    "time"
    "context"
    "encoding/json"
    "github.com/aws/aws-sdk-go/aws"
    "github.com/aws/aws-sdk-go/aws/session"
    "github.com/aws/aws-sdk-go/service/sqs"
    "github.com/aws/aws-sdk-go/service/ssm"
    "github.com/aws/aws-lambda-go/events"
    runtime "github.com/aws/aws-lambda-go/lambda"
)
type MyEvent struct {
    Name string `json:"name"`
}

var (
    useSSMCache string = "true" //override via environment vars
    sqsUrlCache *ssm.GetParameterOutput = nil
    cacheExpires int64 = 0
)
const cacheTimeout int64 = 60

func sqsSendMessage(message string) (*sqs.SendMessageOutput, error) {
    sqsUrl, err  := getSqsUrl();
    if err != nil {
        return nil, err
    }

    sess := session.Must(session.NewSessionWithOptions(session.Options {
        Config: aws.Config{
            Region: aws.String(os.Getenv("AWS_REGION")),
        },
    }))

    sqsService := sqs.New(sess)
    sqsResult, err := sqsService.SendMessage(&sqs.SendMessageInput{
        MessageBody: aws.String(message),
        QueueUrl: sqsUrl.Parameter.Value,
        DelaySeconds: aws.Int64(0),
    })
    if err != nil {
        return nil, err
    }
    return sqsResult, nil
}

func getSqsUrl() (*ssm.GetParameterOutput, error) {
    val, ok := os.LookupEnv("USE_SSM_CACHE")
    if ok {
        useSSMCache = val
    }

    if(useSSMCache == "true" || useSSMCache == "TRUE"){
        if(sqsUrlCache != nil){
            if(time.Now().Unix() < cacheExpires) {
                fmt.Println("SQS Url from cache")
                return sqsUrlCache, nil
            }
        }
    }
    sess := session.Must(session.NewSessionWithOptions(session.Options {
        Config: aws.Config{
            Region: aws.String(os.Getenv("AWS_REGION")),
        },
    }))

    ssmService := ssm.New(sess)

    sqsUrl, err  := ssmService.GetParameter(&ssm.GetParameterInput{
        Name: aws.String("sqs_url"),
    })
    if err != nil {
        return nil, err
    }
    if(useSSMCache == "true" || useSSMCache == "TRUE"){
        fmt.Println("SQS Url not cached or timed out")
        sqsUrlCache = sqsUrl
        t := time.Now()
        cacheExpires = t.Unix() + cacheTimeout
    }
    return sqsUrl, nil
}

func handleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
    //CORS
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
        return events.APIGatewayProxyResponse{
            StatusCode: http.StatusBadRequest,
            Headers: headers,
            Body: "",
            IsBase64Encoded: false,
        }, errors.New("Unmarshal error")
    }

    name := value.Name
    if name == "" {
        return events.APIGatewayProxyResponse{
            StatusCode: http.StatusBadRequest,
            Headers: headers,
            Body: "",
            IsBase64Encoded: false,
        }, errors.New("Name not specified")
    }

    output := fmt.Sprintf("Hello %s", name)

    sqsResult, err := sqsSendMessage(output)
    if err != nil {
        return events.APIGatewayProxyResponse{
            StatusCode: http.StatusBadRequest,
            Headers: headers,
            Body: "",
            IsBase64Encoded: false,
        }, fmt.Errorf("Error %v", err)
    }

    messageId := fmt.Sprintf("%v", sqsResult.MessageId)
    return events.APIGatewayProxyResponse{
        StatusCode: http.StatusOK,
        Headers: headers,
        Body: "{ \"result\": \""+output+"\", \"sqs\": \""+messageId+"\" }",
        IsBase64Encoded: false,
    }, nil
}
func main() {
    runtime.Start(handleRequest)
}
