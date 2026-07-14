package main

import (
	"fmt"
	"os"
)

const version = "marshald 0.0.0-dev"

func main() {
	fmt.Fprintln(os.Stdout, version)
}
