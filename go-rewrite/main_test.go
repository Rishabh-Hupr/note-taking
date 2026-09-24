//go:build sqlite_fts5

package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDataDir_EnvOverride(t *testing.T) {
	t.Setenv("BUTLER_DATA_DIR", "/tmp/butler-test-xyz")
	got, err := dataDir()
	if err != nil {
		t.Fatal(err)
	}
	if got != "/tmp/butler-test-xyz" {
		t.Errorf("dataDir=%q want /tmp/butler-test-xyz", got)
	}
}

func TestDataDir_DefaultsToDotButler(t *testing.T) {
	t.Setenv("BUTLER_DATA_DIR", "")
	got, err := dataDir()
	if err != nil {
		t.Fatal(err)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(home, ".butler"); got != want {
		t.Errorf("dataDir=%q want %q", got, want)
	}
}

func TestBestEffortID(t *testing.T) {
	cases := []struct {
		line string
		want int
	}{
		{`{"id":42,"cmd":"put"}`, 42},
		{`{"cmd":"x"}`, 0},
		{`not json at all`, 0},
	}
	for _, c := range cases {
		if got := bestEffortID([]byte(c.line)); got != c.want {
			t.Errorf("bestEffortID(%q)=%d want %d", c.line, got, c.want)
		}
	}
}
