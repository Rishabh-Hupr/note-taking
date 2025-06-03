package main

import (
	"github.com/ncruces/zenity"
	// "main/setup_database"
)

const DBPath = "/Users/machupr/note-taking/go-rewrite/db"

func errorCheck(err error) bool {
	if err != nil {
		println("Something wrong happened")
		return false
	}
	return true
}

func main() {
	// var key string
	// var value string
	input, err := zenity.Entry("Enter the key", zenity.Title("Storing note..."))
	if errorCheck(err) {
		println("Key", input, "was input")
	}

	value, err := zenity.Entry("Enter the value", zenity.Title("Storing note..."))
	if errorCheck(err) {
		println("Entered value", value)
	}

	// key_reader := bufio.NewReader(os.Stdin)
	// print("Enter key: ")
	// key, err := key_reader.ReadString('\n')
	// if err != nil {
	// 	println("Something wrong happend 🚨")
	// 	return
	// }

	// value_reader := bufio.NewReader(os.Stdin)
	// print("Enter value: ")
	// value, err := value_reader.ReadString('\n')
	// if err != nil {
	// 	println("Something wrong happened 🚨")
	// 	return
	// }
	// store := map[string]string{}
	// store[key] = value

	// val, ok := store[key]

	// if ok {
	// 	print("Key found", val)
	// } else {
	// 	print("Hey hey hey, it's not something you ever stored")
	// }
}
