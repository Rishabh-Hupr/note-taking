package helpers

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
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

func exists(path string) bool { _, err := os.Stat(path); return err == nil }

// useLog points the logger at path for one test and resets everything after.
func useLog(t *testing.T, path string) {
	t.Helper()
	SetLogPath(path)
	t.Cleanup(func() {
		SetStderrToLog(false)
		SetLogPath("")
		rotationPausedUntil = time.Time{}
	})
}

func TestLogIt_BelowLimitAppends(t *testing.T) {
	log := filepath.Join(t.TempDir(), "app.log")
	write(t, log, "existing\n")
	useLog(t, log)

	LogIt("new line")

	got := read(t, log)
	if !strings.HasPrefix(got, "existing\n") || !strings.Contains(got, "new line") {
		t.Errorf("log under the limit should just be appended to, got %q", got)
	}
	if exists(log + ".1") {
		t.Error("no backup expected below the limit")
	}
}

func TestLogIt_RotatesOnceTheTrackedSizeCrossesTheLimit(t *testing.T) {
	// Size is counted as we write (no stat per line): the write that crosses the
	// limit goes into the current file, and the next one starts a fresh log.
	log := filepath.Join(t.TempDir(), "app.log")
	write(t, log, strings.Repeat("x", MaxLogBytes-10))
	useLog(t, log)

	LogIt("this line crosses the limit")
	if exists(log + ".1") {
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

func TestLogIt_RotationShiftsBackupsAndKeepsOnlyN(t *testing.T) {
	log := filepath.Join(t.TempDir(), "app.log")
	write(t, log+".1", "one")
	write(t, log+".2", "two")
	write(t, log+".3", "three") // oldest: must be dropped
	write(t, log, strings.Repeat("x", MaxLogBytes))
	useLog(t, log)

	LogIt("new")

	for suffix, want := range map[string]string{".2": "one", ".3": "two"} {
		if got := read(t, log+suffix); got != want {
			t.Errorf("%s = %q, want %q", suffix, got, want)
		}
	}
	if !strings.HasPrefix(read(t, log+".1"), "xxxx") {
		t.Error("the full log should be .1")
	}
	if exists(log + ".4") {
		t.Error("only 3 backups should be kept")
	}
}

func TestLogIt_FailedRotationLosesNothing(t *testing.T) {
	// The directory becomes unwritable at rotation time: the full log and every
	// backup must stay as they were, and logging must carry on.
	dir := t.TempDir()
	log := filepath.Join(dir, "app.log")
	write(t, log+".1", "one")
	write(t, log+".2", "two")
	write(t, log+".3", "three")
	write(t, log, strings.Repeat("x", MaxLogBytes))
	useLog(t, log)
	if err := os.Chmod(dir, 0500); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(dir, 0700)

	LogIt("still logging")
	LogIt("and again")

	os.Chmod(dir, 0700)
	for suffix, want := range map[string]string{".1": "one", ".2": "two", ".3": "three"} {
		if got := read(t, log+suffix); got != want {
			t.Errorf("backup %s = %q, want %q (a failed rotation must not shift backups)", suffix, got, want)
		}
	}
	if got := read(t, log); !strings.Contains(got, "still logging") || !strings.Contains(got, "and again") {
		t.Error("logging should continue into the current file after a failed rotation")
	}
}

func TestLogIt_RecoversWhenTheLogIsDeletedByHand(t *testing.T) {
	log := filepath.Join(t.TempDir(), "app.log")
	saved := logRecheckInterval
	logRecheckInterval = 0 // re-check on every line, so the test needn't wait
	defer func() { logRecheckInterval = saved }()
	useLog(t, log)

	LogIt("before")
	os.Remove(log)
	LogIt("after")

	if got := read(t, log); !strings.Contains(got, "after") {
		t.Errorf("a deleted log should be recreated, got %q", got)
	}
}

func TestLogIt_UsesPrivatePermissions(t *testing.T) {
	log := filepath.Join(t.TempDir(), "app.log")
	write(t, log, "x")
	os.Chmod(log, 0644) // a log created before logs were private
	useLog(t, log)
	LogIt("line")

	info, err := os.Stat(log)
	if err != nil {
		t.Fatal(err)
	}
	if perm := info.Mode().Perm(); perm != 0600 {
		t.Errorf("log permissions = %o, want 600", perm)
	}
}

func TestSetStderrToLog_StderrFollowsTheLogAcrossRotation(t *testing.T) {
	// Panic traces go to stderr: they must land in the current app.log, both
	// right away and after a rotation (never in the rotated-away app.log.1).
	log := filepath.Join(t.TempDir(), "app.log")
	saved, err := syscall.Dup(int(os.Stderr.Fd()))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { syscall.Dup2(saved, int(os.Stderr.Fd())); syscall.Close(saved) }()
	write(t, log, strings.Repeat("x", MaxLogBytes))
	useLog(t, log)
	SetStderrToLog(true)

	LogIt("trigger rotation")
	os.Stderr.WriteString("panic trace\n")

	if !strings.Contains(read(t, log), "panic trace") {
		t.Error("stderr output after rotation should go to the fresh app.log")
	}
	if strings.Contains(read(t, log+".1"), "panic trace") {
		t.Error("stderr output must not land in the rotated-away app.log.1")
	}
}
