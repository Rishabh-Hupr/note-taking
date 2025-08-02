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
    * Something like below:
    ```
        type User struct {
            name string
            age int
        }
    ```
    is basically a new data type that has the above defined structure
    And then you can have functions that define a struct as a receiver something similar to self in python that can be used to call the parameters of the object, in Go it works something like below:
    ```
        func (u User) function_name() string {
            println(u.name, u.age)
        }
    ```
    * You can have functions which can be callable from stuct objects, the one above could be called something like this:
    ```
        new_user := User{
            name: "Rish",
            age: 20
        }

        new_user.function_name()
    ```
    * You can also have nested structs, and define functions on those nested structs as well, and those functions would still be callable fby the parent stuct of the nested struct, letting you enjoy the encapsulation magic. Goes something like this:
    ```
        type Address struct {
            city string
            state string
        }

        type User struct {
            name string
            age int
            Address
        }

        type User struct {
            name string
            age int
            addrs Address
        }

        func (a Address) print_address() {
            println(a.city, a.state)
        
        }
        func (u User) print_user() {
            println(u.name, u.age)
        }


        func main() {
            address := Address {
                city: "Gurgaon",
                state: "Haryana"
            }
            new_user := User{
                name: "Rish",
                age: 20,
                Address: address
            }
            new_user.print_address()
        }

        THIS THING ONLY WORKS IF YOU HAVE THE NESTED STRUCT DEFINED AS THE NAME OF THE STRUCT ITSELF AND NOT LIKE ``address Address``, i.e. LINE 75 ✅ would work, but not LINE 81 ❌
    ```
    * ONE THING THAT IS STILL TO BE CONFIRMED IS, can you play with structs without having stuct functions??????

    CONFIRMED, it can still work with just having normal functions check below:
    ```
        type Addrs struct {
            city  string
            state string
        }

        type User struct {
            name string
            age  int
            Addrs
        }

        func (a Addrs) print_address() string {
            return a.city + ", " + a.state
        }

        func (u User) print_user() {
            fmt.Println(u.name, u.age, u.print_address())
        }

        func playingWithStruct(u *User) {
            u.print_user()
            u.name = "Broooooo"
        }

        func main() {
            address := Addrs{
                city:  "BSR",
                state: "UP",
            }
            user := User{
                name:  "Rish",
                age:   24,
                Addrs: address,
            }

            //	user.print_user()
            playingWithStruct(&user)
            user.print_user()
        }

    ```

    * You can also have interfaces in go which basically lets you have a code something like this:
    ```
        type Speaker interface {
            Speak() string
        }

        type Dog struct {}
        func (Dog) Speak() string {
            return "Woof!! Woof!!"
        }

        type Cat struct {}
        func (Cat) Speak() string {
            return "Meow!! Meooowww!!"
        }

        func printSpeaker(s Speaker) string {
            print(s.Speak())
        }

        func main() {
            printSpeaker(Dog{})
            printSpeaker(Cat{})
        }
    ```
    * Good thing about interfaces is that you can re-use the type your have created if any struct follows the interface contract(i.e. any struct that implements all the interface defined methods), hence will allow you to use the interface as datatype for playing in the code
        NOTE: This is how CustomException can be defined in GoLang
        Because the source code of go has
        ```
            type error interface {
                Error() string
            }
        ```

        Hence you can do any custom `ErrorStruct` and then you can create an `Error` function for the same `ErrorStruct` and then it will be made available by the `error` type to be usable across the code for error handling
    