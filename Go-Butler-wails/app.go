package main

import (
	"GoButler"
	"GoButler/dao"
	"context"
	"database/sql"
	"fmt"
	"log"

	"github.com/wailsapp/wails/v2/pkg/runtime"
	"golang.design/x/hotkey"
)

// App struct
type App struct {
	ctx    context.Context
	db     *sql.DB
	dbPath string
}

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{}
}

// startup is called at application startup
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	a.dbPath = "/Users/machupr/note-taking/go-rewrite/db"
	db, err := GoButler.NewNotesDatabase(a.dbPath)
	fmt.Println("Database path: " + a.dbPath)
	if err != nil {
		// Handle error appropriately
		panic(err)
	}
	a.db = db.Db
	// Hotkey registration must be done here, in OnStartup, because it needs
	// to be on the main thread, and it needs the app context.

	// Register fetch hotkey
	fetchHk := hotkey.New([]hotkey.Modifier{hotkey.ModCtrl, hotkey.ModOption}, hotkey.KeyG)
	err = fetchHk.Register()
	if err != nil {
		log.Printf("hotkey registration failed for Ctrl+Option+G: %v", err)
	} else {
		log.Printf("hotkey: Ctrl+Option+G is registered")
	}

	// Register note hotkey
	noteHk := hotkey.New([]hotkey.Modifier{hotkey.ModCtrl, hotkey.ModOption}, hotkey.KeyK)
	err = noteHk.Register()
	if err != nil {
		log.Printf("hotkey registration failed for Ctrl+Option+K: %v", err)
	} else {
		log.Printf("hotkey: Ctrl+Option+K is registered")
	}

	// Start a goroutine to listen for hotkey events
	go func() {
		for {
			select {
			case <-fetchHk.Keydown():
				fmt.Println("Ctrl+Option+G pressed")
				runtime.EventsEmit(a.ctx, "FetchEvent")
			case <-noteHk.Keydown():
				fmt.Println("Ctrl+Option+K pressed")
				runtime.EventsEmit(a.ctx, "NoteEvent")
			}
		}
	}()
}

// domReady is called after front-end resources have been loaded
func (a App) domReady(ctx context.Context) {
	// Add your action here
}

// beforeClose is called when the application is about to quit,
// either by clicking the window close button or calling runtime.Quit.
// Returning true will cause the application to continue, false will continue shutdown as normal.
func (a *App) beforeClose(ctx context.Context) (prevent bool) {
	return false
}

// shutdown is called at application termination
func (a *App) shutdown(ctx context.Context) {
	// Perform your teardown here
}

// FetchNote retrieves a note by its key
func (a *App) FetchNote(key string) map[string]string {
	return dao.FetchNote(a.db, key)
}

// PutNote stores a new note
func (a *App) PutNote(key, value string) {
	dao.PutNote(a.db, key, value)
}

// ShowDB retrieves all notes
func (a *App) ShowDB() map[string]string {
	return dao.ShowDB(a.db)
}
