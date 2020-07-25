package main

import (
    "fmt"
    "os"
    "io/ioutil"
    "bytes"
    "github.com/tidwall/gjson"
)

func main() {
    input, err := ioutil.ReadAll(os.Stdin)
    if err != nil {
        os.Exit(1)
    }

    //remove makefile cruft if make not run with silent
    input = input[bytes.IndexRune(input, '{'):]
    inputString  := string(input)

    aws_project_region := gjson.Get(inputString, "aws_project_region.value")
    aws_cognito_region := gjson.Get(inputString, "aws_cognito_region.value")
    aws_cognito_identity_pool_id := gjson.Get(inputString, "aws_cognito_identity_pool_id.value")
    aws_user_pools_id := gjson.Get(inputString, "aws_user_pools_id.value")
    aws_user_pools_web_client_id := gjson.Get(inputString, "aws_user_pools_web_client_id.value")

    fmt.Fprint(os.Stdout, "const awsmobile = {\n")
    fmt.Fprint(os.Stdout, "  \"aws_project_region\": \"", aws_project_region.String(), "\",\n")
    fmt.Fprint(os.Stdout, "  \"aws_cognito_region\": \"", aws_cognito_region.String(), "\",\n")
    fmt.Fprint(os.Stdout, "  \"aws_cognito_identity_pool_id\": \"", aws_cognito_identity_pool_id.String(), "\",\n")
    fmt.Fprint(os.Stdout, "  \"aws_user_pools_id\": \"", aws_user_pools_id.String(), "\",\n")
    fmt.Fprint(os.Stdout, "  \"aws_user_pools_web_client_id\": \"", aws_user_pools_web_client_id.String(), "\",\n")
    fmt.Fprint(os.Stdout, "};\n");
    fmt.Fprint(os.Stdout, "export default awsmobile\n");
}
