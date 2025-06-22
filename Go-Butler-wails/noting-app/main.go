package GoButler

import (
	"GoButler/dao"
	"GoButler/utils"
	"database/sql"
	"fmt"

	"github.com/ncruces/zenity"
	"golang.design/x/clipboard"
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
	var selectedItem string
	if len(args) > 0 {
		selectedItem, err = zenity.ListItems("Fetched Results", args...)
		if utils.Error_happened(err) {
			var errorString = fmt.Sprintf("‼️ %s", err)
			zenity.Info(errorString)
			return
		}
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

func RunApp() {
	db, err := NewNotesDatabase(DBPath)
	if utils.Error_happened(err) {
		return
	}

	// fetch(db.db)

	note(db.db)
}
