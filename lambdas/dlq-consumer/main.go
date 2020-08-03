package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/aws/aws-lambda-go/events"
	runtime "github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sns"
	"github.com/aws/aws-sdk-go/service/ssm"
)

//SQSBody json struct
type DLQBody struct {
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

func handler(ctx context.Context, sqsEvent events.SQSEvent) error {

	for _, message := range sqsEvent.Records {

		fmt.Printf("[%s %s] Message = %s\n", message.MessageId, message.EventSource, message.Body)

		body := &DLQBody{}

		err := json.Unmarshal([]byte(message.Body), body)
		if err != nil {
			return err
		}

		dlqTopicArn, err := getParameterStoreValue("dlq_topic_arn")
		if err != nil {
			return err
		}

		if sess == nil {
			sess = session.Must(session.NewSessionWithOptions(session.Options{
				Config: aws.Config{
					Region: aws.String(os.Getenv("AWS_REGION")),
				},
			}))
		}

		snsService := sns.New(sess)
		params := &sns.PublishInput{
			Message:  aws.String("DLQ notification"),
			TopicArn: dlqTopicArn.Parameter.Value,
		}

		res, err := snsService.Publish(params)
		if err != nil {
			return err
		}

		fmt.Println(res)

	}
	return nil
}

func main() {
	runtime.Start(handler)
}
