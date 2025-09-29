package main

import (
	"net/http"
)

type TracedClient struct {
	client *http.Client
}

func (c *TracedClient) Do(req *http.Request) (*http.Response, error) {
	// No-op tracing: usar cliente stdlib
	return c.client.Do(req)
}

// initTracing devuelve un middleware no-op y un cliente HTTP estándar
func initTracing(_ string) (func(http.Handler) http.Handler, *TracedClient, error) {
	mw := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			next.ServeHTTP(w, r)
		})
	}
	return mw, &TracedClient{client: http.DefaultClient}, nil
}
