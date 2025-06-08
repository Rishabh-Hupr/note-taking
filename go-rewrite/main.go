package main

import (
	"Go-Butler/dao"
	"Go-Butler/utils"
	"fmt"

	"github.com/ncruces/zenity"
)

const DBPath = "/Users/machupr/note-taking/go-rewrite/db"

func main() {
	// var key string
	// var value string
	input, err := zenity.Entry("Enter the key", zenity.Title("Storing note..."))
	if utils.Error_happened(err) {
		return
	}
	println("Key", input, "was input")

	value, err := zenity.Entry("Enter the value", zenity.Title("Storing note..."))
	if utils.Error_happened(err) {
		return
	}
	println("Entered value", value)

	db, err := NewNotesDatabase(DBPath)
	if utils.Error_happened(err) {
		return
	}

	wholeDatabase := dao.ShowDB(db.db)
	fmt.Println(wholeDatabase)

}
