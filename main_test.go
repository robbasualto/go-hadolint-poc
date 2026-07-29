package main

import "testing"

func TestGreeting(t *testing.T) {
	tests := []struct {
		name string
		want string
	}{
		{"canonical greeting", "Hello, world!"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := greeting(); got != tt.want {
				t.Errorf("greeting() = %q, want %q", got, tt.want)
			}
		})
	}
}
