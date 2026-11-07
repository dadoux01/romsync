package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func unwritableDir(t *testing.T) string {
	t.Helper()
	if os.Getuid() == 0 {
		t.Skip("root can write anywhere")
	}
	dir := filepath.Join(t.TempDir(), "data")
	if err := os.Mkdir(dir, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(dir, 0o700) })
	return dir
}

func TestCheckDataDirExplainsPermissionProblems(t *testing.T) {
	dir := unwritableDir(t)
	err := checkDataDir(dir)
	if err == nil {
		t.Fatal("expected an error")
	}
	ids := fmt.Sprintf("%d:%d", os.Getuid(), os.Getgid())
	for _, want := range []string{dir, "not writable", ids, "chown -R " + ids} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("message lacks %q: %v", want, err)
		}
	}
	if err := checkDataDir(filepath.Join(dir, "sub")); err == nil || !strings.Contains(err.Error(), "cannot be created") {
		t.Errorf("unexpected error for a missing directory: %v", err)
	}
	if err := checkDataDir(t.TempDir()); err != nil {
		t.Errorf("a writable directory must pass: %v", err)
	}
}

func TestFatalErrorsExitNonZero(t *testing.T) {
	t.Setenv("ROMSYNC_DATA_DIR", unwritableDir(t))
	t.Setenv("ROMSYNC_PORT", "18999")
	if code := realMain(nil); code == 0 {
		t.Fatal("an unwritable data directory must give a non-zero exit code")
	}
	t.Setenv("ROMSYNC_PORT", "not-a-port")
	if code := realMain(nil); code == 0 {
		t.Fatal("an invalid configuration must give a non-zero exit code")
	}
}
