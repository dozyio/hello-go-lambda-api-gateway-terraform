package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/aws/aws-lambda-go/events"
	runtime "github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/dynamodb/dynamodbattribute"
	"github.com/aws/aws-sdk-go/service/ssm"
)

//Item to hold sqs info for insert into dynamodb
type Item struct {
	Pkey        string `json:"pkey"`
	Skey        string `json:"skey"`
	MessageID   string `json:"messageId"`
	EventSource string `json:"eventSource"`
	Body        string `json:"body"`
}

//SQSBody json struct
type SQSBody struct {
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
	useSSMCache    string           = "true"  //override via environment vars
	alwaysError    string           = "false" //override via environment vars - for testing DLQ
	parameterStore                  = make(map[string]SSMParameterStoreCache)
	cacheTimeout   int64            = cacheDefaultTimeout
	sess           *session.Session = nil
)

func getParameterStoreValue(param string) (*ssm.GetParameterOutput, error) {
	if val, ok := os.LookupEnv("USE_SSM_CACHE"); ok {
		useSSMCache = val
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
		if val, ok := os.LookupEnv("SSM_CACHE_TIMEOUT"); ok {
			if timeout, err := strconv.ParseInt(val, 10, 64); err == nil {
				if timeout >= 0 {
					cacheTimeout = timeout
				}
			}
		}

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

func handler(ctx context.Context, sqsEvent events.SQSEvent) error {
	if val, ok := os.LookupEnv("ALWAYS_ERROR"); ok {
		alwaysError = val
	}

	if alwaysError == "true" || alwaysError == "TRUE" {
		return errors.New("ALWAYS_ERROR = true")
	}

	if sess == nil {
		sess = session.Must(session.NewSessionWithOptions(session.Options{
			Config: aws.Config{
				Region: aws.String(os.Getenv("AWS_REGION")),
			},
		}))
	}

	dynamodbService := dynamodb.New(sess)

	tableName, err := getParameterStoreValue("dynamodb_table_name")
	if err != nil {
		return err
	}

	for _, message := range sqsEvent.Records {

		fmt.Printf("[%s %s] Message = %s\n", message.MessageId, message.EventSource, message.Body)

		body := &SQSBody{}

		err := json.Unmarshal([]byte(message.Body), body)
		if err != nil {
			return err
		}

		dt := time.Now()
		item := Item{
			Pkey:        body.Type + "#" + body.Value,
			Skey:        dt.Format(time.RFC3339Nano),
			MessageID:   message.MessageId,
			EventSource: message.EventSource,
			Body:        message.Body,
		}

		av, err := dynamodbattribute.MarshalMap(item)
		if err != nil {
			fmt.Printf("Error marshaling")
			fmt.Printf(err.Error())
			return err
		}

		fmt.Printf("%v", av)

		input := &dynamodb.PutItemInput{
			Item:      av,
			TableName: tableName.Parameter.Value,
		}

		output, err := dynamodbService.PutItem(input)
		if err != nil {
			return err
		}
		fmt.Println(output)
	}
	return nil
}

func main() {
	runtime.Start(handler)
}
