---
title: "Getting started with Go kit"

categories: ["Golang"]

date: 2023-04-15 00:00:00 +1100

modified: 2023-04-15 00:00:00 +1100

authors: [akshay]

excerpt: "Go kit is quite popular among the developers. In this article, we will build a microservice and leverage go kit."

image: images/stock/golang.png

url: getting-started-with-go-kit

popup: false
---

I am so excited to start this journey. This is my blogging website where I am planning to write tech/travel/random blogs, feel free to hop on this journey with me. 6 months back I started working at a startup where we use golang extensively. Being a primarrily java developer, I started questioning some of the design aspects of golang but it took me a month to be convinced that its the future, mine at least. We use godev kit (wrapper on top of go kit) for building microservices and believe me you will love the simplicity of the language, clean architecture, best practises go kit provides, including but not limited to design patterns like circuit breaker, rate limiting, distributed tracing, etc. So lets go on a journey.

Before starting you must be familiar with the terms like transport, endpoint, service

- **_Transport_** - The transport domain is bound to concrete transports like HTTP, gRPC, msgPack, AMPQ, etc. We can support all this transport domain in a single microservice and I believe this is very powerful.

- **_Endpoint_** - An endpoint is like and action/ handler on a controller. Its where safety and antifragiel logic lives. If you implement two transports, you might have two methods of sending requests to the same endpoint.

- **_Services_** - Services are where all of the business logic is implemented. A service usually glues together mutliple endpoints. In Go kit, services are typically modelled as interfaces and implementation of those interfaces contain the business logic. Go kit services should strive to abide the Hexagonal Architecuter, i.e the business logic should have no knowledge of endpoint - or especially transport domain concepts.

## Example

Let's create an example of a microservice using this architecture. The directory structure looks like this:
{{% image alt="Code structure" src="images/stock/gokit_example.png" %}}

### Service

The service layer code in this example is very simple:

```java
package user

import (
    "auth/security"
    "context"
    "errors"
)

type Service interface {
    ValidateUser(ctx context.Context, mail, password string) (string, error)
    ValidateToken(ctx context.Context, token string) (string, error)
}

var (
    ErrInvalidUser  = errors.New("Invalid user")
    ErrInvalidToken = errors.New("Invalid token")
)

type service struct{}

func NewService() *service {
    return &service{}
}

func (s *service) ValidateUser(ctx context.Context, email, password string) (string, error) {
    //@TODO create validation rules, using databases or something else
    if email == "eminetto@gmail.com" && password != "1234567" {
        return "nil", ErrInvalidUser
    }
    token, err := security.NewToken(email)
    if err != nil {
        return "", err
    }
    return token, nil
}

func (s *service) ValidateToken(ctx context.Context, token string) (string, error) {
    t, err := security.ParseToken(token)
    if err != nil {
        return "", ErrInvalidToken
    }
    tData, err := security.GetClaims(t)
    if err != nil {
        return "", ErrInvalidToken
    }
    return tData["email"].(string), nil
```

As the Go kit documentation recommends, the first step is to create an `interface` for our service, which will be implemented with our business logic. Soon, this decision to create an interface will prove useful when we include logging and monitoring metrics in the application.

### Endpoint

We will now expose our functions to the outside world. In this example the two functions will be able to be accessed externally, so we will create two endpoints. But this is not always true. Depending on the scenario you can expose only a few functions and keep the others accessible only within the service layer.

```java
package user

import (
    "context"

    "github.com/go-kit/kit/endpoint"
)

//definition of endpoint input and output structures
type validateUserRequest struct {
    Email    string `json:"email"`
    Password string `json:"password"`
}

type validateUserResponse struct {
    Token string `json:"token,omitempty"`
    Err   string `json:"err,omitempty"` // errors don't JSON-marshal, so we use a string
}

//the endpoint will receive a request, convert to the desired
//format, invoke the service and return the response structure
func makeValidateUserEndpoint(svc Service) endpoint.Endpoint {
    return func(ctx context.Context, request interface{}) (interface{}, error) {
        req := request.(validateUserRequest)
        token, err := svc.ValidateUser(ctx, req.Email, req.Password)
        if err != nil {
            return validateUserResponse{"", err.Error()}, err
        }
        return validateUserResponse{token, ""}, err
    }
}

//definition of endpoint input and output structures
type validateTokenRequest struct {
    Token string `json:"token"`
}

type validateTokenResponse struct {
    Email string `json:"email,omitempty"`
    Err   string `json:"err,omitempty"`
}

//the endpoint will receive a request, convert to the desired
//format, invoke the service and return the response structure
func makeValidateTokenEndpoint(svc Service) endpoint.Endpoint {
    return func(ctx context.Context, request interface{}) (interface{}, error) {
        req := request.(validateTokenRequest)
        email, err := svc.ValidateToken(ctx, req.Token)
        if err != nil {
            return validateTokenResponse{"", err.Error()}, err
        }
        return validateTokenResponse{email, ""}, err
    }
}

```

The role of the endpoint is to receive a request, convert it to the expected struct, invoke the service layer, and return another struct. The endpoint layer does not know anything about the upper layer, because it makes no difference whether the endpoint is being invoked via HTTP, gRPC, or another form of transport.

### Transport

In this layer, we can have several implementations like HTTP, gRPC, AMPQ, NATS, etc. In this example, we are going to expose our endpoints in the form of an HTTP API. So, we will create the file `transpor_http.go`:

```java
package user

import (
    "context"
    "encoding/json"
    "net/http"

    "github.com/go-kit/kit/log"
    httptransport "github.com/go-kit/kit/transport/http"
    "github.com/gorilla/mux"
)

func NewHttpServer(svc Service, logger log.Logger) *mux.Router {
    //options provided by the Go kit to facilitate error control
    options := []httptransport.ServerOption{
        httptransport.ServerErrorLogger(logger),
        httptransport.ServerErrorEncoder(encodeErrorResponse),
    }
    //definition of a handler
    validateUserHandler := httptransport.NewServer(
        makeValidateUserEndpoint(svc), //use the endpoint
        decodeValidateUserRequest, //converts the parameters received via the request body into the struct expected by the endpoint
        encodeResponse, //converts the struct returned by the endpoint to a json response
        options...,
    )

    validateTokenHandler := httptransport.NewServer(
        makeValidateTokenEndpoint(svc),
        decodeValidateTokenRequest,
        encodeResponse,
        options...,
    )
    r := mux.NewRouter() //I'm using Gorilla Mux, but it could be any other library, or even the stdlib
    r.Methods("POST").Path("/v1/auth").Handler(validateUserHandler)
    r.Methods("POST").Path("/v1/validate-token").Handler(validateTokenHandler)
    return r
}

func encodeErrorResponse(_ context.Context, err error, w http.ResponseWriter) {
    if err == nil {
        panic("encodeError with nil error")
    }
    w.Header().Set("Content-Type", "application/json; charset=utf-8")
    w.WriteHeader(codeFrom(err))
    json.NewEncoder(w).Encode(map[string]interface{}{
        "error": err.Error(),
    })
}

func codeFrom(err error) int {
    switch err {
    case ErrInvalidUser:
        return http.StatusNotFound
    case ErrInvalidToken:
        return http.StatusUnauthorized
    default:
        return http.StatusInternalServerError
    }
}

//converts the parameters received via the request body into the struct expected by the endpoint
func decodeValidateUserRequest(ctx context.Context, r *http.Request) (interface{}, error) {
    var request validateUserRequest
    if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
        return nil, err
    }
    return request, nil
}

//converts the parameters received via the request body into the struct expected by the endpoint
func decodeValidateTokenRequest(ctx context.Context, r *http.Request) (interface{}, error) {
    var request validateTokenRequest
    if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
        return nil, err
    }
    return request, nil
}

//converts the struct returned by the endpoint to a json response
func encodeResponse(ctx context.Context, w http.ResponseWriter, response interface{}) error {
    return json.NewEncoder(w).Encode(response)
}

```

### Main

In the `main.go` file we are going to use all the layers:

```java
package main

import (
    "auth/user"
    "net/http"
    "os"

    "github.com/go-kit/kit/log"
)

func main() {

    var logger log.Logger
    logger = log.NewLogfmtLogger(os.Stderr)
    logger = log.With(logger, "listen", "8081", "caller", log.DefaultCaller)

    svc := user.NewLoggingMiddleware(logger, user.NewService())
    r := user.NewHttpServer(svc, logger)
    logger.Log("msg", "HTTP", "addr", "8081")
    logger.Log("err", http.ListenAndServe(":8081", r))
}
```

Here we can see another advantage in having created an interface for our service. The `user.NewHttpServer` function expects as a first parameter something that implements the `Service` interface. The `user.NewLoggingMiddleware` function creates a struct that implements this interface and has our original service inside it. The code for the `logging.go` file looks like this:

```java
package user

import (
    "context"
    "time"

    "github.com/go-kit/kit/log"
)

func NewLoggingMiddleware(logger log.Logger, next Service) logmw {
    return logmw{logger, next}
}

type logmw struct {
    logger log.Logger
    Service
}

func (mw logmw) ValidateUser(ctx context.Context, email, password string) (token string, err error) {
    defer func(begin time.Time) {
        _ = mw.logger.Log(
            "method", "validateUser",
            "input", email,
            "err", err,
            "took", time.Since(begin),
        )
    }(time.Now())

    token, err = mw.Service.ValidateUser(ctx, email, password)
    return
}

func (mw logmw) ValidateToken(ctx context.Context, token string) (email string, err error) {
    defer func(begin time.Time) {
        _ = mw.logger.Log(
            "method", "validateToken",
            "input", token,
            "err", err,
            "took", time.Since(begin),
        )
    }(time.Now())

    email, err = mw.Service.ValidateToken(ctx, token)
    return
}
```

It implements all the functions of the interface, adding the functionality of logging each function call, before invoking the code of the real service. The same can be used to implement metrics, limit access to API, etc. In the official tutorial, we have [some examples](https://gokit.io/examples/stringsvc.html#application-instrumentation) of this.

If our microservice needs to deliver the logic in more formats, such as gRPC or NATS, we would only need to implement these codes in the transport layer indicating which endpoints will be used. This gives a lot of flexibility for the growth of functionalities without increasing complexity.
