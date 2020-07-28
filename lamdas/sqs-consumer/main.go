package main

import (
    "context"
    "fmt"
    "github.com/aws/aws-lambda-go/events"
    runtime "github.com/aws/aws-lambda-go/lambda"
)

func handler (ctx context.Context, sqsEvent events.SQSEvent) error{
    for _, message := range sqsEvent.Records {
        fmt.Printf("[%s %s] Message = %s\n", message.MessageId, message.EventSource, message.Body)
    }
    return nil
}

func main(){
    runtime.Start(handler)
}
