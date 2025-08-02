package main

import (
	"Go-Butler/dao"
	"Go-Butler/utils"
	"database/sql"
	"fmt"

	"github.com/ncruces/zenity"
	"golang.design/x/clipboard"
)

const DBPath = "/Users/machupr/note-taking/go-rewrite/db"

func fetch(db *sql.DB) {
	key, err := zenity.Entry("Enter the key", zenity.Title("Fetching note..."))
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

	var selectedItem string
	if len(args) > 0 {
		selectedItem, err = zenity.List("(Hit enter to copy the selected item to clipboard)", args, zenity.Title("Fetched Results"), zenity.OKLabel("📋"), zenity.CancelLabel("Close"))
		if utils.Error_happened(err) {
			return
		}

		// if errors.Is(err, zenity.ErrUnsupported) {
		// 	// lets call the delete function on the selected item
		// 	fmt.Println("Delete button clicked")
		// }
	}
	err = clipboard.Init()
	if err != nil {
		panic(err)
	}
	clipboard.Write(clipboard.FmtText, []byte(selectedItem))
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

	fetch(db.db)

	// note(db.db)
}
