// Command romsync runs the RomSync server: REST API, embedded web interface
// and periodic retention job, in a single binary.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/dadoux01/romsync/server/internal/api"
	"github.com/dadoux01/romsync/server/internal/blobs"
	"github.com/dadoux01/romsync/server/internal/config"
	"github.com/dadoux01/romsync/server/internal/db"
	"github.com/dadoux01/romsync/server/internal/retention"
	"github.com/dadoux01/romsync/server/internal/updates"
	"github.com/dadoux01/romsync/server/internal/webui"
)

// version is set at build time (-ldflags "-X main.version=…").
var version = "dev"

func main() {
	// Single exit point: every fatal error ends with a non-zero exit code.
	os.Exit(realMain(os.Args[1:]))
}

// realMain runs the program and returns its exit code.
func realMain(args []string) int {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, nil)))
	// `romsync healthcheck` is used by the container health check: the
	// distroless image has no shell nor curl.
	if len(args) > 0 && args[0] == "version" {
		fmt.Println(version)
		return 0
	}
	if len(args) > 0 && args[0] == "healthcheck" {
		if err := healthcheck(); err != nil {
			fmt.Fprintln(os.Stderr, "unhealthy:", err)
			return 1
		}
		return 0
	}
	if err := run(); err != nil {
		slog.Error("fatal", "err", err)
		return 1
	}
	return 0
}

func run() error {
	cfg, err := config.FromEnv()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := checkDataDir(cfg.DataDir); err != nil {
		return err
	}
	conn, err := db.Open(ctx, filepath.Join(cfg.DataDir, "romsync.db"))
	if err != nil {
		return fmt.Errorf("database: %w", err)
	}
	defer conn.Close()

	store, err := blobs.New(filepath.Join(cfg.DataDir, "blobs"))
	if err != nil {
		return fmt.Errorf("blob store: %w", err)
	}

	job := &retention.Job{DB: conn, Blobs: store, BlobDir: filepath.Join(cfg.DataDir, "blobs"), Now: time.Now}
	go job.Run(ctx, cfg.RetentionInterval)

	var relay *updates.Relay
	if cfg.Updates {
		relay = updates.NewRelay(cfg.UpdateRepo, cfg.GitHubToken, filepath.Join(cfg.DataDir, "updates"))
		go relay.Run(ctx, cfg.UpdateInterval)
	}

	srv := api.New(api.Options{DB: conn, Blobs: store, Config: cfg, Version: version, Updates: relay})
	httpSrv := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Port),
		Handler:           srv.Handler(webui.Handler()),
		ReadHeaderTimeout: 10 * time.Second,
	}

	errc := make(chan error, 1)
	go func() {
		slog.Info("listening", "version", version, "port", cfg.Port, "data_dir", cfg.DataDir,
			"updates", cfg.Updates, "update_repo", cfg.UpdateRepo)
		errc <- httpSrv.ListenAndServe()
	}()

	select {
	case err := <-errc:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
		slog.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := httpSrv.Shutdown(shutdownCtx); err != nil {
			return err
		}
	}
	return nil
}

func healthcheck() error {
	cfg, err := config.FromEnv()
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 3 * time.Second}
	res, err := client.Get(fmt.Sprintf("http://127.0.0.1:%d/healthz", cfg.Port))
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("status %d", res.StatusCode)
	}
	return nil
}

// checkDataDir makes sure the data directory exists and is writable, and
// explains how to fix it otherwise: the usual cause is a volume owned by
// another user than the container's (65532:65532).
func checkDataDir(dir string) error {
	uid, gid := os.Getuid(), os.Getgid()
	hint := func(problem string, err error) error {
		return fmt.Errorf("data directory %s %s (%v). The server runs as uid:gid %d:%d; "+
			"give it the directory, for example on the host: sudo chown -R %d:%d <directory mounted on %s>",
			dir, problem, err, uid, gid, uid, gid, dir)
	}
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return hint("cannot be created", err)
	}
	st, err := os.Stat(dir)
	if err != nil {
		return hint("cannot be read", err)
	}
	if !st.IsDir() {
		return fmt.Errorf("data directory %s is not a directory", dir)
	}
	f, err := os.CreateTemp(dir, ".write-test-*")
	if err != nil {
		return hint("is not writable", err)
	}
	name := f.Name()
	f.Close()
	if err := os.Remove(name); err != nil {
		return hint("is not writable", err)
	}
	return nil
}
