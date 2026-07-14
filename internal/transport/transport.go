// Package transport exposes one Unix-domain-socket endpoint per device and
// bridges a single guest connection at a time to the device plugin.
package transport

import (
	"context"
	"log/slog"
	"net"
	"os"
	"sync/atomic"

	"github.com/Mile-High-Ideas/marshal/internal/plugin"
)

// Transport is one device's Unix-socket endpoint.
type Transport struct {
	name   string
	socket string
	plug   plugin.Plugin
	log    *slog.Logger
	ln     net.Listener
	busy   atomic.Bool
}

// New builds a transport for a device. Call Start, then Serve.
func New(name, socket string, p plugin.Plugin, log *slog.Logger) *Transport {
	return &Transport{name: name, socket: socket, plug: p, log: log}
}

// Name returns the device name.
func (t *Transport) Name() string { return t.name }

// Start removes any stale socket and binds the listener.
func (t *Transport) Start() error {
	_ = os.Remove(t.socket)
	ln, err := net.Listen("unix", t.socket)
	if err != nil {
		return err
	}
	t.ln = ln
	return nil
}

// Serve accepts guest connections until ctx is cancelled or the listener is
// closed. Exactly one guest is bridged at a time; a second concurrent
// connection is refused (closed). Cancelling ctx stops Serve and returns nil.
func (t *Transport) Serve(ctx context.Context) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	// Closing the listener is the only way to unblock Accept, so close it when
	// ctx is cancelled — this lets a caller stop Serve with ctx alone. The
	// derived ctx + defer cancel() guarantees this watcher exits when Serve does.
	go func() {
		<-ctx.Done()
		_ = t.ln.Close()
	}()
	for {
		conn, err := t.ln.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		if !t.busy.CompareAndSwap(false, true) {
			t.log.Warn("refusing second concurrent guest", "device", t.name)
			_ = conn.Close()
			continue
		}
		go t.handle(ctx, conn)
	}
}

func (t *Transport) handle(ctx context.Context, conn net.Conn) {
	defer t.busy.Store(false)
	cctx, cancel := context.WithCancel(ctx)
	defer cancel()
	// bridge.Pump (inside plug.Pump) closes conn on return.
	if err := t.plug.Pump(cctx, conn); err != nil {
		t.log.Error("pump ended with error", "device", t.name, "err", err)
		return
	}
	t.log.Info("guest disconnected", "device", t.name)
}

// Close stops accepting and removes the socket file.
func (t *Transport) Close() error {
	var err error
	if t.ln != nil {
		err = t.ln.Close()
	}
	_ = os.Remove(t.socket)
	return err
}
