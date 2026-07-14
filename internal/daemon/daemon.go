// Package daemon wires config + plugins + transports into a runnable daemon.
package daemon

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sync"

	"github.com/Mile-High-Ideas/marshal/internal/config"
	"github.com/Mile-High-Ideas/marshal/internal/plugin"
	"github.com/Mile-High-Ideas/marshal/internal/transport"
)

// Daemon owns the devices and their transports for one process lifetime.
type Daemon struct {
	cfg    *config.Config
	reg    *plugin.Registry
	log    *slog.Logger
	runDir string
}

// New builds a daemon. runDir is where per-device sockets are created.
func New(cfg *config.Config, reg *plugin.Registry, log *slog.Logger, runDir string) *Daemon {
	return &Daemon{cfg: cfg, reg: reg, log: log, runDir: runDir}
}

// Run builds and opens every device, serves each on its socket, blocks until
// ctx is cancelled, then shuts down cleanly. Any startup failure aborts with a
// clean partial teardown.
func (d *Daemon) Run(ctx context.Context) error {
	if err := os.MkdirAll(d.runDir, 0o700); err != nil {
		return fmt.Errorf("daemon: runtime dir: %w", err)
	}

	var opened []plugin.Plugin
	var transports []*transport.Transport
	closeAll := func() {
		for _, t := range transports {
			_ = t.Close()
		}
		for i := len(opened) - 1; i >= 0; i-- {
			_ = opened[i].Close()
		}
	}

	for _, dev := range d.cfg.Devices {
		p, err := d.reg.Build(dev)
		if err != nil {
			closeAll()
			return fmt.Errorf("daemon: device %q: %w", dev.Name, err)
		}
		opened = append(opened, p) // track before Open so a failed Open is still closed
		if err := p.Open(ctx); err != nil {
			closeAll()
			return fmt.Errorf("daemon: open %q: %w", dev.Name, err)
		}

		sock := filepath.Join(d.runDir, dev.Socket)
		tr := transport.New(dev.Name, sock, p, d.log)
		transports = append(transports, tr) // track before Start
		if err := tr.Start(); err != nil {
			closeAll()
			return fmt.Errorf("daemon: listen %q: %w", dev.Name, err)
		}
	}

	var wg sync.WaitGroup
	for _, tr := range transports {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := tr.Serve(ctx); err != nil {
				d.log.Error("serve stopped", "device", tr.Name(), "err", err)
			}
		}()
	}
	d.log.Info("marshald running", "devices", len(transports), "runDir", d.runDir)

	<-ctx.Done()
	d.log.Info("shutting down")
	// Close listeners first so no new guests are accepted; ctx cancellation
	// unwinds any in-flight Pump. Join all Serve goroutines BEFORE closing the
	// devices, so no goroutine is still using a plugin when it is closed.
	for _, tr := range transports {
		_ = tr.Close()
	}
	wg.Wait()
	for i := len(opened) - 1; i >= 0; i-- {
		_ = opened[i].Close()
	}
	return nil
}
