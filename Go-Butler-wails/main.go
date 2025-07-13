package main

import (
	"embed"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
)

//go:embed all:frontend/dist
var assets embed.FS

// //go:embed build/appicon.png
// var icon []byte

func main() {
	// Create an instance of the app structure
	app := NewApp()

	// Create application with options
	wails.Run(&options.App{
		Title:     "wails-events",
		Width:     700,
		Height:    100,
		Assets:    assets,
		Frameless: true,
		OnStartup: app.startup,
		Bind: []interface{}{
			app,
		},

		Mac: &mac.Options{
			Appearance:           mac.NSAppearanceNameDarkAqua,
			WebviewIsTransparent: true,
			WindowIsTranslucent:  true,
		},
	})

}
