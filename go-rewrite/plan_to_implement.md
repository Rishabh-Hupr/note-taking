## Plan

1. ✅ Write a file to create the db file and all the necessary tables and stuff
2. ✅ Write another file that checks if the DB exists or not
	* ✅ If not, then call the first file
	* ✅ If yes, then just get the connection to the db file and move on
3. ✅ Write another piece of code for fetching or putting logic
4. ✅ Hook everything with current main.go file, because that does the job of actually doing stuff from UI
5. ✅ Modularize the configs as in python
6. ✅ FOR GODs sake find a way to setup keyboard shortcut globally on system level from the code itself
7. ✅ Research about RayCast kind of UI to make it more intuitive
	* ✅ Install [wails UI](https://wails.io/docs/introduction) framework
   	* ✅ Install node, npm
	* ❌ [wails-vite-react-ts-tailwind-template](https://github.com/hotafrika/wails-vite-react-ts-tailwind-template) - A template for React + TypeScript + Vite + TailwindCSS
		#### WAILS didn't suffice the need for exact raycast like UI, there was always a white background screen which stays there no matter you get rid of all of the CSS code, checked few issues on github still no such working solution found. 
		#### It also didn't work like the native Go implementation is working in terms of listening for global keyboard shortcuts, it could listen for once the application goes in running, still NOT A GLOBAL KEYBOARD SHORTCUT
	* ❌ Restructure the existing directory for wails Framework or create another one for the same
8. 👨🏻‍💻 Create binaries for both fetching & noting functionality and then create their own automator quickActions
9. ❌ Work on auto-focusing the "Fetched Results" screen in fetch functionality
10. ❌ Adding delete functionality for the stored notes from zenity UIs
#### Deprecating the zenity integration, because of an obstacle when it comes to deleting feature for a note. Here is the issue that I opened: https://github.com/ncruces/zenity/issues/150
11. 🎬 Looking into putting this Butler in a CLI App, using BubbleTea at the moment, though we have some other options:
  * GoCUI
  * Termui
  
**NOTE**:  RATIONALE behind Bubbletea is that it is `well-documented` & `event-driven` TUI.

12. 🎬 Put the Note functionality behind a BubbleTea App
13. 🎬 Put the Fetch functionality behind another BubbleTea App
14. 🎬 Weigh if it is better to have different binaries for fetch & note or Just one binary for fetching and noting
15. 🎬 Come up with a first MVP and test it out.



## 💡 Latest Idea bouncing session with ChatGPT
Q: So far everything in the whole app and go language, and I was trying to use zenity to create some visual pop-ups on the screen for storing a note or fetching a note and trying to add functionality to delete the note on that, however I don't think that's visible and I feel that it's not so intuitive and s common because the window doesn't changes the focus to the notes window automatically so now I'm thinking about a different approach that is, I want to create it in SCLI format so that as soon as someone hits, the keyboard shortcuts are for fetching or putting a note in the storage so for noting functionality, I don't think I need to have some kind of you. I accept the basic text boxes that will help you with the note however for fetching functionality, I would rather want to see all the notes in CLI so imagine I had a keyboard shortcut. It asks me for a note that I want to fetch in a CLI so that a terminal opens and I put in my key and then I hit enter and then I put in my value that I want to store the key and then it's all set back. I already have the business logic of storing and fetch in the note. The only thing that I'm sending is how to produce that data so I'm thinking to use or build my own tool in NCL format so that a terminal opens up which if you want to fetch a note, you fetch a note against your stored keys and you will get a bunch of notes which which which match your ke and you can navigate through those notes using keyboard up and down keys so that you can basically navigate those notes and if you hit backspace or D on your keyboard, that note should get deleted if you had enter on any of those notes that will get copied to your clipboard

A:
This is an excellent pivot — you're describing a **CLI-first productivity tool** with keyboard-driven note access, and that can be a **highly effective, developer-friendly product niche**. Let's lock down your vision and then design the system around it.

## 🧠 Summary of Your New Idea

You're building a:

> **Keyboard-triggered terminal note interface**
> Where:
>
> * ⌨️ Keyboard shortcut opens terminal window (SCLI format)
> * 🧠 You type a key → fetch notes matching the key
> * ⬆️⬇️ Use up/down to navigate matches
> * ↩️ `Enter` → copies note to clipboard
> * 🅧 `Backspace` or `D` → deletes the note

You **already have**:

* Written in **Go**
* Logic for **storing, fetching notes**
* Original attempt using Ziti (UI pop-ups) felt non-intuitive

You want to:

* Make it **CLI-first**
* Make it feel **fast**, **keyboard-native**, and **invisible** when idle

This is a solid shift — you’re aligning with developer tools like `fzf`, `ripgrep`, `pass`, and `tldr` — tools devs love because they're fast and keyboard-centric.

---

## 🛠️ Suggested Architecture

### 🏗️ Structure:

* CLI app (built in Go)
* Global keyboard shortcut (calls the CLI app with a specific mode)
* Notes stored in lightweight storage (can be JSON, BoltDB, or simple files)
* Output rendered in terminal UI (TUI)
* Clipboard integration
* Terminal behavior: minimal, popup style (like `fzf` or `rofi`)

---

## 🔧 Components You’ll Need

### 1. **Global Shortcut to Launch Terminal Tool**

* On **macOS**: use `Automator`, `hammerspoon`, or `raycast` to trigger your app
* On **Linux**: `xdotool`, `rofi`, or custom keybind via WM
* On **Windows**: AutoHotKey or `Run` + keybind

The shortcut should run your CLI binary with a mode, like:

```bash
notecli fetch
notecli put
```

---

### 2. **TUI Framework (for CLI interaction)**

Use a Go TUI library like:

| Library                                                   | Pros                     | Notes                   |
| --------------------------------------------------------- | ------------------------ | ----------------------- |
| [`bubbletea`](https://github.com/charmbracelet/bubbletea) | Modern, event-driven TUI | Very well-documented    |
| [`gocui`](https://github.com/jroimartin/gocui)            | Lightweight, Curses-like | Less abstract, more raw |
| [`termui`](https://github.com/gizak/termui)               | Great for dashboards     | Might be overkill here  |

📌 **Recommended:** Start with `bubbletea` — ergonomic and expressive.

---

### 3. **Clipboard Integration**

Use `github.com/atotto/clipboard` in Go:

```go
import "github.com/atotto/clipboard"

err := clipboard.WriteAll("my copied note")
```

---

### 4. **Storage Layer**

You said it’s already done — but here's a note:

* If you're using something like BoltDB or SQLite — great.
* Keep it simple: `map[string][]string` logic works with JSON too.

---

### 5. **Search + Display**

* When the user runs `notecli fetch`, show:

  * A prompt asking for the **key or keyword**
  * Matching notes displayed below
  * Highlighted note changes as user presses ⬆️⬇️
* Enter = copy
* D or Backspace = delete

You can even add fuzzy search later (`fzf`-style).

---

### 🧪 Sample CLI Interaction (MVP Sketch)

```bash
$ notecli fetch

> Search: pro

  [1] project ideas - “build AI chatbot”
  [2] progress log - “completed module A”
  [3] promotion tips - “ask for feedback…”

Use ↑ ↓ to navigate. [Enter] to copy. [D] to delete.
```

---

## 🚀 Suggested Phases

### ✅ Phase 1: MVP

* `notecli fetch` with a prompt, list, navigation
* `notecli put` that opens a textbox (raw input)
* Storage layer (file or BoltDB)
* Clipboard support

### 🔥 Phase 2: Add polish

* Fuzzy search
* Syntax highlighting (markdown notes)
* Tags or note metadata
* Configurable keyboard shortcuts
* Auto-launch CLI from system-wide hotkey

### 🧩 Phase 3: Monetization & Distribution

* Package as CLI binary for all platforms
* Offer Pro version:

  * Encrypted storage
  * Sync via Git or Dropbox
  * Templated note types
  * Web UI for reviewing archive

---

## 🎯 Business Angle (CLI-first Tool)

You're now in a good niche:

| Target Users      | Needs                      |
| ----------------- | -------------------------- |
| Developers        | Fast access, keyboard-only |
| Writers/coders    | Low-distraction tools      |
| Privacy nerds     | Local storage, no cloud    |
| Linux/macOS users | Prefer CLI over GUI bloat  |

---

## ✅ Next Steps

1. **Pick your TUI lib**: `bubbletea` recommended
2. Want help with a **starter Go project skeleton** for this CLI?
3. Want help writing the `notecli fetch` interactive part?

Let me know which part you want to build next — and I can generate some starter code or design for it.

---


Q: can I do live searches using fzf on buttle tea screen?

A:
Great question — you're trying to combine the **live fuzzy-search power of `fzf`** with the **custom UI and interaction control of `bubbletea`**. Here's the short version:

---

## ✅ **Can you do live fuzzy searching in a `bubbletea` screen?**

### **Yes, but not directly using `fzf` itself — you’ll need to:**

* Implement **fuzzy matching in Go** (there are libraries)
* Re-render the filtered list inside a `bubbletea` `Model` as the user types

---

## 🔍 Why you can’t (easily) embed `fzf` into `bubbletea`

`fzf` is a standalone TUI app — it **takes over the terminal** using its own UI. So you can't run it *inside* a `bubbletea` app the way you'd embed a widget.

But you **can replicate fzf-like behavior** inside `bubbletea` using Go libraries.

---

## 🛠️ How to Do Fuzzy Search in `bubbletea`

### 1. Use a fuzzy matching library in Go:

| Library                                                                                             | Description              |
| --------------------------------------------------------------------------------------------------- | ------------------------ |
| [`github.com/lithammer/fuzzysearch`](https://github.com/lithammer/fuzzysearch)                      | Simple and effective     |
| [`github.com/sahilm/fuzzy`](https://github.com/sahilm/fuzzy)                                        | Fast and ranked matching |
| [`github.com/renstrom/fuzzysearch/fuzzy`](https://pkg.go.dev/github.com/renstrom/fuzzysearch/fuzzy) | Older but usable         |

📌 Recommended: [`sahilm/fuzzy`](https://github.com/sahilm/fuzzy)

Example usage:

```go
matches := fuzzy.Find("search term", listOfNotes)
```

---

### 2. In your `bubbletea.Model`, store:

```go
type Model struct {
    input string          // what the user is typing
    matches []string      // currently filtered notes
    allNotes []string     // full unfiltered list
    selectedIndex int     // for arrow navigation
}
```

On every keystroke:

* Update `input`
* Run `fuzzy.Find(input, allNotes)` to get `matches`
* Update the UI accordingly

---

### 3. Handle key messages

In your `Update()` function, handle:

* Character keys (to update the `input`)
* `Enter` (to copy to clipboard)
* `D` or `Backspace` (to delete)
* Arrow keys (to move through `matches`)

---

## 🧪 Example Interaction

```
Search: pro

> [x] project planning - “next sprint goals”
  [ ] progress log - “finished module B”
  [ ] profile notes - “user study feedback”

⬆️⬇️ to move | ↩️ to copy | D to delete
```

---

## 🧰 Want a Starter Template?

I can give you:

* A minimal `bubbletea` program
* With a fuzzy search input box
* That shows a filtered list
* And copies the selected note to clipboard with `Enter`

Would you like me to generate that now?
