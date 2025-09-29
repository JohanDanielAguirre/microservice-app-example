package main

import (
	"context"
	"encoding/json"
    "errors"
	"log"
	"net/http"
    "net"
	"os"
	"time"

	jwt "github.com/golang-jwt/jwt/v4"
	"github.com/labstack/echo"
	"github.com/labstack/echo/middleware"
	gommonlog "github.com/labstack/gommon/log"
    "github.com/sony/gobreaker"
    "strconv"
)

var (
	// ErrHttpGenericMessage that is returned in general case, details should be logged in such case
	ErrHttpGenericMessage = echo.NewHTTPError(http.StatusInternalServerError, "something went wrong, please try again later")

	// ErrWrongCredentials indicates that login attempt failed because of incorrect login or password
	ErrWrongCredentials = echo.NewHTTPError(http.StatusUnauthorized, "username or password is invalid")

	jwtSecret string
)

func main() {
	hostport := ":" + os.Getenv("AUTH_API_PORT")
	userAPIAddress := os.Getenv("USERS_API_ADDRESS")

	envJwtSecret := os.Getenv("JWT_SECRET")
	if len(envJwtSecret) == 0 {
		log.Fatal("JWT_SECRET environment variable is required")
	}
	jwtSecret = envJwtSecret

	userService := UserService{
		Client:         http.DefaultClient,
		UserAPIAddress: userAPIAddress,
		AllowedUserHashes: map[string]interface{}{
			"admin_admin": nil,
			"johnd_foo":   nil,
			"janed_ddd":   nil,
		},
	}

    // Circuit Breaker configuration via environment variables
    if os.Getenv("CB_ENABLED") == "1" || os.Getenv("CB_ENABLED") == "true" {
        timeoutMs, _ := strconv.Atoi(defaultIfEmpty(os.Getenv("CB_TIMEOUT_MS"), "2000"))
        resetTimeoutMs, _ := strconv.Atoi(defaultIfEmpty(os.Getenv("CB_RESET_TIMEOUT_MS"), "10000"))
        errorThreshold, _ := strconv.Atoi(defaultIfEmpty(os.Getenv("CB_ERROR_THRESHOLD"), "5"))
        requestTimeoutMs, _ := strconv.Atoi(defaultIfEmpty(os.Getenv("CB_REQUEST_TIMEOUT_MS"), "1500"))

        st := gobreaker.Settings{
            Name:        "users-api-cb",
            Timeout:     time.Duration(timeoutMs) * time.Millisecond,
            ReadyToTrip: func(counts gobreaker.Counts) bool { return int(counts.ConsecutiveFailures) >= errorThreshold },
            Interval:    0,
            MaxRequests: 1,
        }
        // Log state transitions explicitly
        st.OnStateChange = func(name string, from, to gobreaker.State) {
            log.Printf("circuit-breaker '%s' state change: %s -> %s", name, stateToString(from), stateToString(to))
        }
        // Reset timeout controls open->half-open transition
        if resetTimeoutMs > 0 {
            st.Timeout = time.Duration(resetTimeoutMs) * time.Millisecond
        }
        userService.Breaker = gobreaker.NewCircuitBreaker(st)
        if requestTimeoutMs > 0 {
            userService.RequestTimeout = time.Duration(requestTimeoutMs) * time.Millisecond
        }
    }

	e := echo.New()
	e.Logger.SetLevel(gommonlog.INFO)

	e.Use(middleware.Logger())
	e.Use(middleware.Recover())
	
	// Security headers
	e.Use(middleware.SecureWithConfig(middleware.SecureConfig{
		XSSProtection:         "1; mode=block",
		ContentTypeNosniff:    "nosniff",
		XFrameOptions:         "DENY",
		HSTSMaxAge:            3600,
	}))
	
	// CORS with proper configuration
	e.Use(middleware.CORSWithConfig(middleware.CORSConfig{
		AllowOrigins: []string{"http://localhost:8080", "http://127.0.0.1:8080"},
		AllowMethods: []string{echo.GET, echo.POST, echo.PUT, echo.DELETE, echo.OPTIONS},
		AllowHeaders: []string{echo.HeaderOrigin, echo.HeaderContentType, echo.HeaderAccept, echo.HeaderAuthorization},
		MaxAge:       86400,
	}))
	
	// Custom error handler
	e.HTTPErrorHandler = func(err error, c echo.Context) {
		if he, ok := err.(*echo.HTTPError); ok {
			c.JSON(he.Code, map[string]interface{}{
				"error": he.Message,
			})
		} else {
			c.Logger().Error(err)
			c.JSON(http.StatusInternalServerError, map[string]interface{}{
				"error": "Internal server error",
			})
		}
	}

	// Route => handler
	e.GET("/version", func(c echo.Context) error {
		return c.String(http.StatusOK, "Auth API, written in Go\n")
	})

	e.POST("/login", getLoginHandler(userService))

	// Start server
	e.Logger.Fatal(e.Start(hostport))
}

// defaultIfEmpty returns fallback when s is empty
func defaultIfEmpty(s, fallback string) string {
    if s == "" { return fallback }
    return s
}

// stateToString converts gobreaker.State to human-readable text
func stateToString(s gobreaker.State) string {
    switch s {
    case gobreaker.StateClosed:
        return "closed"
    case gobreaker.StateHalfOpen:
        return "half-open"
    case gobreaker.StateOpen:
        return "open"
    default:
        return "unknown"
    }
}

type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func getLoginHandler(userService UserService) echo.HandlerFunc {
	f := func(c echo.Context) error {
		requestData := LoginRequest{}
		decoder := json.NewDecoder(c.Request().Body)
		if err := decoder.Decode(&requestData); err != nil {
			c.Logger().Errorf("could not read credentials from POST body: %s", err.Error())
			return echo.NewHTTPError(http.StatusBadRequest, "Invalid request body")
		}
		
		// Validate input
		if requestData.Username == "" || requestData.Password == "" {
			return echo.NewHTTPError(http.StatusBadRequest, "Username and password are required")
		}

		ctx := c.Request().Context()
		user, err := userService.Login(ctx, requestData.Username, requestData.Password)
		if err != nil {
			// Map circuit breaker open state or context deadlines to 503
			if err == context.DeadlineExceeded {
				return echo.NewHTTPError(http.StatusServiceUnavailable, "users service timeout")
			}
            if errors.Is(err, gobreaker.ErrOpenState) || errors.Is(err, gobreaker.ErrTooManyRequests) {
                return echo.NewHTTPError(http.StatusServiceUnavailable, "users service unavailable (circuit open)")
            }
            var netErr net.Error
            if errors.As(err, &netErr) {
                return echo.NewHTTPError(http.StatusServiceUnavailable, "users service network error")
            }
			if err == ErrInvalidCredentials {
				return ErrWrongCredentials
			}
			
			c.Logger().Errorf("could not authorize user '%s': %s", requestData.Username, err.Error())
			return ErrHttpGenericMessage
		}
		token := jwt.New(jwt.SigningMethodHS256)

		// Set claims
		claims := token.Claims.(jwt.MapClaims)
		claims["username"] = user.Username
		claims["firstname"] = user.FirstName
		claims["lastname"] = user.LastName
		claims["role"] = user.Role
		claims["exp"] = time.Now().Add(time.Hour * 72).Unix()

		// Generate encoded token and send it as response.
		t, err := token.SignedString([]byte(jwtSecret))
		if err != nil {
			c.Logger().Errorf("could not generate a JWT token: %s", err.Error())
			return ErrHttpGenericMessage
		}

		return c.JSON(http.StatusOK, map[string]string{
			"accessToken": t,
		})
	}

	return echo.HandlerFunc(f)
}
