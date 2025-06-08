package utils

import (
	"fmt"
)

func Error_happened(err error) bool {
	if err != nil {
		fmt.Println("Something wrong happened", err)
		return true
	}
	return false
}
