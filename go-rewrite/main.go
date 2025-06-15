package main

import (
	"Go-Butler/dao"
	"Go-Butler/utils"
	"database/sql"
	"fmt"

	"github.com/ncruces/zenity"
)

const DBPath = "/Users/machupr/note-taking/go-rewrite/db"

func fetch(db *sql.DB) {
	key, err := zenity.Entry("Enter the key", zenity.Title("Storing note..."))
	if utils.Error_happened(err) {
		return
	}
	var output map[string]string

	if key == "" {
		// checking ShowDB function
		output = dao.ShowDB(db)
	} else {
		// checking FetchNote function
		output = dao.FetchNote(db, key)
	}
	var args []string
	for key, value := range output {
		args = append(args, fmt.Sprintf("%s: %s", key, value))
	}

	selectedItem, err := zenity.ListItems("Fetched Results", args...)
	if utils.Error_happened(err) {
		return
	}
	println(selectedItem)
}

func note(db *sql.DB) {
	key, err := zenity.Entry("Enter the key", zenity.Title("Storing note..."))
	if utils.Error_happened(err) {
		return
	}

	value, err := zenity.Entry("Enter the value", zenity.Title("Storing note..."))
	if utils.Error_happened(err) {
		return
	}

	if key == "" || value == "" {
		zenity.Error("‼️ Please enter something in both the dialogs 😉")
		return
	}
	// checking PutNote function
	dao.PutNote(db, key, value)

}

func main() {
	db, err := NewNotesDatabase(DBPath)
	if utils.Error_happened(err) {
		return
	}

	// fetch(db.db)

	note(db.db)
}
