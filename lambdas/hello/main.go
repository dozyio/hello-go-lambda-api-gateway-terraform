package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/aws/aws-lambda-go/events"
	runtime "github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	"github.com/aws/aws-sdk-go/service/ssm"
)

//MyEvent for json request
type MyEvent struct {
	Name string `json:"name"`
}

//SQSJson message format
type SQSJson struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

//SSMParameterStoreCache setup
type SSMParameterStoreCache struct {
	Value        *ssm.GetParameterOutput
	CacheExpires int64
}

const cacheDefaultTimeout int64 = 60

var (
	useSSMCache    string           = "true" //override via environment vars
	parameterStore                  = make(map[string]SSMParameterStoreCache)
	cacheTimeout   int64            = cacheDefaultTimeout
	sess           *session.Session = nil
)

func getParameterStoreValue(param string) (*ssm.GetParameterOutput, error) {
	if val, ok := os.LookupEnv("USE_SSM_CACHE"); ok {
		useSSMCache = val
	}

	if val, ok := os.LookupEnv("SSM_CACHE_TIMEOUT"); ok {
		if timeout, err := strconv.ParseInt(val, 10, 64); err == nil {
			if timeout >= 0 {
				cacheTimeout = timeout
			}
		}
	}

	if useSSMCache == "true" || useSSMCache == "TRUE" {
		if parameter, ok := parameterStore[param]; ok {
			if time.Now().Unix() < parameter.CacheExpires {
				fmt.Printf("Param: %s - from cache\n", param)
				return parameter.Value, nil
			}
		}
	}

	if sess == nil {
		sess = session.Must(session.NewSessionWithOptions(session.Options{
			Config: aws.Config{
				Region: aws.String(os.Getenv("AWS_REGION")),
			},
		}))
	}

	ssmService := ssm.New(sess)

	paramOutput, err := ssmService.GetParameter(&ssm.GetParameterInput{
		Name: aws.String(param),
	})
	if err != nil {
		return nil, err
	}

	if useSSMCache == "true" || useSSMCache == "TRUE" {
		fmt.Printf("Param: %s - not cached\n", param)
		t := time.Now()
		cacheExpires := t.Unix() + cacheTimeout
		p := &SSMParameterStoreCache{
			Value:        paramOutput,
			CacheExpires: cacheExpires,
		}
		parameterStore[param] = *p
	}
	return paramOutput, nil
}

func sqsSendMessage(message string) (*sqs.SendMessageOutput, error) {
	sqsURL, err := getParameterStoreValue("sqs_url")
	if err != nil {
		return nil, err
	}

	if sess == nil {
		sess = session.Must(session.NewSessionWithOptions(session.Options{
			Config: aws.Config{
				Region: aws.String(os.Getenv("AWS_REGION")),
			},
		}))
	}

	sqsService := sqs.New(sess)
	sqsResult, err := sqsService.SendMessage(&sqs.SendMessageInput{
		MessageBody:  aws.String(message),
		QueueUrl:     sqsURL.Parameter.Value,
		DelaySeconds: aws.Int64(0),
	})
	if err != nil {
		return nil, err
	}
	return sqsResult, nil
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
			StatusCode:      http.StatusBadRequest,
			Headers:         headers,
			Body:            "",
			IsBase64Encoded: false,
		}, errors.New("Unmarshal error")
	}

	name := value.Name
	if name == "" {
		return events.APIGatewayProxyResponse{
			StatusCode:      http.StatusBadRequest,
			Headers:         headers,
			Body:            "",
			IsBase64Encoded: false,
		}, errors.New("Name not specified")
	}

	output := fmt.Sprintf("Hello %s", name)

	sqsMessageStruct := &SQSJson{
		Type:  "login",
		Value: name,
	}

	sqsMessageByteString, err := json.Marshal(sqsMessageStruct)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode:      http.StatusBadRequest,
			Headers:         headers,
			Body:            "",
			IsBase64Encoded: false,
		}, errors.New("Marshal error")
	}

	sqsMessageString := string(sqsMessageByteString)

	sqsResult, err := sqsSendMessage(sqsMessageString)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode:      http.StatusBadRequest,
			Headers:         headers,
			Body:            "",
			IsBase64Encoded: false,
		}, fmt.Errorf("Error %v", err)
	}

	messageID := fmt.Sprintf("%v", sqsResult.MessageId)
	return events.APIGatewayProxyResponse{
		StatusCode:      http.StatusOK,
		Headers:         headers,
		Body:            "{ \"result\": \"" + output + "\", \"sqs\": \"" + messageID + "\" }",
		IsBase64Encoded: false,
	}, nil
}
func main() {
	runtime.Start(handleRequest)
}
