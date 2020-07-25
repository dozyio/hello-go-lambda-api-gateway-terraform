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

    gateway_endpoint := gjson.Get(inputString, "gateway_endpoint.value")

    fmt.Fprint(os.Stdout, "export const endpoints = [{\n")
    fmt.Fprint(os.Stdout, "  name: \"hello\",\n")
    fmt.Fprint(os.Stdout, "  endpoint: \"", gateway_endpoint.String(), "\"\n")
    fmt.Fprint(os.Stdout, "}];\n");
}
