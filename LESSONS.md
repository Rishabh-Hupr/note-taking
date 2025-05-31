## Lessons
* Ensure that you copy the automator quick action file from the right location i.e. `~/Library/Services`, and from no where else.
* Ensure that your db and log file path is correct in the application i.e. `notes.py` and `utils.py` file

## TODO
1. For God's sake learn GO now
2. ~~Add a way to pass configs to the application~~
3. Make the UI more user friendly

### Go learning todos next steps
1. File import export/Multi-file go compilation
    * It works in a manner that you can have multiple `.go` files in the same directory but **ensure that there is only one `main` function**
    * You can also have sub modules in this structure
        ```
            myapp/
            ├── main.go              // package main
            └── utils/
                └── utils.go                // package utils
                └── onemoreUtils.go         // package utils
        ```
        but then ensure that `myapp` is initialized with `go mod init myapp` and then you will have to import `utils` folder something like this
        ```
            import "myapp/utils"

            // refer utils.go functions using
            utils.someFunction()            // some function in either onemoreUtils or utils
        ```
        and all the files under `utils` should specify that they are package `utils`, because **Go compiles all the functions and all the files in a folder as a package**.
        So `function_names` across all the files in a package reference are supposed to be unique too

2. Dependencies kaha store hoti h
    * Go dependencies are stored in `~/go/pkg/mod` and you can define import to internet git repositories that have a valid `go.mod` file and when you run or build your application along with dependencies go will automatically fetch those and put them in the above folder and add them to go.mod and go.sum file
    * Remember this 👇🏻
      | Purpose                   | Path (default)     | Notes                            |
      | ------------------------- | ------------------ | -------------------------------- |
      | Global module cache       | `~/go/pkg/mod`     | Where all your dependencies live |
      | Module build cache        | `~/go/pkg/cache`   | Stores compiled build artifacts  |
      | Project-specific `go.mod` | `<project>/go.mod` | Declares required modules        |
      | Project-specific `go.sum` | `<project>/go.sum` | Verifies versions and integrity  |

3. Structs and classes counterparts of python in go