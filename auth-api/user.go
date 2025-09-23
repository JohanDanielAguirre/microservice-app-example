package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/sony/gobreaker"
	jwt "github.com/golang-jwt/jwt/v4"
    "time"
)

// Business logic errors
var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrUserNotFound      = errors.New("user not found")
	ErrUserServiceError  = errors.New("user service error")
)

type User struct {
	Username  string `json:"username"`
	FirstName string `json:"firstname"`
	LastName  string `json:"lastname"`
	Role      string `json:"role"`
}

type HTTPDoer interface {
	Do(req *http.Request) (*http.Response, error)
}

type UserService struct {
	Client            HTTPDoer
	UserAPIAddress    string
	AllowedUserHashes map[string]interface{}
    Breaker           *gobreaker.CircuitBreaker
    RequestTimeout    time.Duration
}

func (h *UserService) Login(ctx context.Context, username, password string) (User, error) {
	user, err := h.getUser(ctx, username)
	if err != nil {
		return user, err
	}

	userKey := fmt.Sprintf("%s_%s", username, password)

	if _, ok := h.AllowedUserHashes[userKey]; !ok {
		return user, ErrInvalidCredentials
	}

	return user, nil
}

func (h *UserService) getUser(ctx context.Context, username string) (User, error) {
	var user User

    exec := func() (User, error) {
        token, err := h.getUserAPIToken(username)
        if err != nil {
            return user, err
        }
        url := fmt.Sprintf("%s/users/%s", h.UserAPIAddress, username)
        req, _ := http.NewRequest("GET", url, nil)
        req.Header.Add("Authorization", "Bearer "+token)

        // Apply per-request timeout if configured
        requestCtx := ctx
        if h.RequestTimeout > 0 {
            var cancel context.CancelFunc
            requestCtx, cancel = context.WithTimeout(ctx, h.RequestTimeout)
            defer cancel()
        }
        req = req.WithContext(requestCtx)

        resp, err := h.Client.Do(req)
        if err != nil {
            return user, err
        }

        defer resp.Body.Close()
        bodyBytes, err := io.ReadAll(resp.Body)
        if err != nil {
            return user, err
        }

        if resp.StatusCode < 200 || resp.StatusCode >= 300 {
            return user, fmt.Errorf("could not get user data: %s", string(bodyBytes))
        }

        err = json.Unmarshal(bodyBytes, &user)
        return user, err
    }

    // Use circuit breaker if configured
    if h.Breaker != nil {
        v, err := h.Breaker.Execute(func() (interface{}, error) {
            return exec()
        })
        if err != nil {
            return user, err
        }
        if u, ok := v.(User); ok {
            return u, nil
        }
        return user, ErrUserServiceError
    }

    return exec()
}

func (h *UserService) getUserAPIToken(username string) (string, error) {
	token := jwt.New(jwt.SigningMethodHS256)
	claims := token.Claims.(jwt.MapClaims)
	claims["username"] = username
	claims["scope"] = "read"
	return token.SignedString([]byte(jwtSecret))
}
