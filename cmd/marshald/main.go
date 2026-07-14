// Command marshald bridges macOS-side devices to Parallels guest apps.
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/Mile-High-Ideas/marshal/internal/config"
	"github.com/Mile-High-Ideas/marshal/internal/daemon"
	"github.com/Mile-High-Ideas/marshal/internal/plugin"
	"github.com/Mile-High-Ideas/marshal/internal/plugins/aim"
	"github.com/Mile-High-Ideas/marshal/internal/plugins/mock"
	"github.com/Mile-High-Ideas/marshal/internal/plugins/serial"
)

func main() {
	configPath := flag.String("config", "", "path to the TOML config file")
	flag.Parse()

	log := slog.New(slog.NewTextHandler(os.Stderr, nil))

	if *configPath == "" {
		log.Error("missing required -config flag")
		os.Exit(2)
	}
	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Error("load config", "err", err)
		os.Exit(1)
	}

	reg := plugin.NewRegistry()
	reg.Register("mock", mock.New)
	reg.Register("serial", serial.New)
	reg.Register("aim-sw4", aim.New)

	home, err := os.UserHomeDir()
	if err != nil {
		log.Error("resolve home dir", "err", err)
		os.Exit(1)
	}
	runDir := filepath.Join(home, ".marshald", "run")

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	d := daemon.New(cfg, reg, log, runDir)
	if err := d.Run(ctx); err != nil {
		log.Error("daemon exited", "err", err)
		os.Exit(1)
	}
}
