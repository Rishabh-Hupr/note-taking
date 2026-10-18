package helpers

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestLogIt_BelowLimitAppends(t *testing.T) {
	log := filepath.Join(t.TempDir(), "app.log")
	write(t, log, "existing\n")
	SetLogPath(log)
	defer SetLogPath("")

	LogIt("new line")

	got := read(t, log)
	if !strings.HasPrefix(got, "existing\n") || !strings.Contains(got, "new line") {
		t.Errorf("log under the limit should just be appended to, got %q", got)
	}
	if _, err := os.Stat(log + ".1"); err == nil {
		t.Error("no backup expected below the limit")
	}
}

func TestLogIt_RotatesOnceTheTrackedSizeCrossesTheLimit(t *testing.T) {
	// The size is counted as we write (no stat per line): the write that crosses
	// the limit goes into the current file, and the next one starts a fresh log.
	log := filepath.Join(t.TempDir(), "app.log")
	write(t, log, strings.Repeat("x", MaxLogBytes-10))
	SetLogPath(log)
	defer SetLogPath("")

	LogIt("this line crosses the limit")
	if _, err := os.Stat(log + ".1"); err == nil {
		t.Fatal("should not rotate before the limit has been reached")
	}
	LogIt("first line of the new log")

	if !strings.Contains(read(t, log+".1"), "crosses the limit") {
		t.Error("the full log should have moved to .1")
	}
	if got := read(t, log); !strings.Contains(got, "first line of the new log") || strings.Contains(got, "xxxx") {
		t.Errorf("fresh log should hold only the new line, got %d bytes", len(got))
	}
}

func TestRotateFiles_ShiftsBackupsAndKeepsOnlyN(t *testing.T) {
	log := filepath.Join(t.TempDir(), "app.log")
	write(t, log+".1", "one")
	write(t, log+".2", "two")
	write(t, log+".3", "three") // oldest: must be dropped
	write(t, log, "current")

	rotateFiles(log, 3)

	if _, err := os.Stat(log); err == nil {
		t.Error("current log should have moved to .1")
	}
	for suffix, want := range map[string]string{".1": "current", ".2": "one", ".3": "two"} {
		if got := read(t, log+suffix); got != want {
			t.Errorf("%s = %q, want %q", suffix, got, want)
		}
	}
	if _, err := os.Stat(log + ".4"); err == nil {
		t.Error("only 3 backups should be kept")
	}
}

func TestLogIt_RotatesAndUsesPrivatePermissions(t *testing.T) {
	log := filepath.Join(t.TempDir(), "app.log")
	write(t, log, strings.Repeat("x", MaxLogBytes)) // already at the limit
	SetLogPath(log)
	defer SetLogPath("")

	LogIt("fresh line")

	if !strings.Contains(read(t, log), "fresh line") || strings.Contains(read(t, log), "xxxx") {
		t.Error("LogIt should rotate the full log away and start a fresh one")
	}
	info, err := os.Stat(log)
	if err != nil {
		t.Fatal(err)
	}
	if perm := info.Mode().Perm(); perm != 0600 {
		t.Errorf("new log permissions = %o, want 600", perm)
	}
}

func TestLogIt_RepointsStderrAfterRotation(t *testing.T) {
	// Simulate the app handing us the log as stderr, then rotate: a later stderr
	// write (e.g. a panic trace) must land in the fresh app.log, not app.log.1.
	log := filepath.Join(t.TempDir(), "app.log")
	write(t, log, strings.Repeat("x", MaxLogBytes))
	saved, err := syscall.Dup(int(os.Stderr.Fd()))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { syscall.Dup2(saved, int(os.Stderr.Fd())); syscall.Close(saved) }()
	f, err := os.OpenFile(log, os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	syscall.Dup2(int(f.Fd()), int(os.Stderr.Fd()))
	f.Close()

	SetLogPath(log)
	SetStderrFollowsLog(true)
	defer func() { SetLogPath(""); SetStderrFollowsLog(false) }()

	LogIt("trigger rotation")
	os.Stderr.WriteString("panic trace\n")

	if !strings.Contains(read(t, log), "panic trace") {
		t.Error("stderr output after rotation should go to the fresh app.log")
	}
	if strings.Contains(read(t, log+".1"), "panic trace") {
		t.Error("stderr output must not land in the rotated-away app.log.1")
	}
}
