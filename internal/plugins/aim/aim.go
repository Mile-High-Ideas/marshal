package aim

import (
	"context"
	"errors"
	"io"
	"net"
	"os"

	"github.com/Mile-High-Ideas/marshal/internal/config"
	"github.com/Mile-High-Ideas/marshal/internal/plugin"
)

// Default AiM SW4 USB identity.
const (
	defaultVID uint16 = 0x11CC
	defaultPID uint16 = 0x0110
)

// New constructs an AiM SW4 plugin. VID/PID default to 0x11CC/0x0110 and are
// overridable via the device's [usb] config block.
func New(cfg config.Device) (plugin.Plugin, error) {
	vid, pid := defaultVID, defaultPID
	if cfg.USB != nil {
		if cfg.USB.VID != 0 {
			vid = uint16(cfg.USB.VID)
		}
		if cfg.USB.PID != 0 {
			pid = uint16(cfg.USB.PID)
		}
	}
	p := &aimPlugin{vid: vid, pid: pid}
	p.open = func() (usbDevice, error) { return openDevice(p.vid, p.pid) }
	return p, nil
}

type aimPlugin struct {
	vid, pid uint16
	open     func() (usbDevice, error) // seam; overridden by the replay test
	dev      usbDevice
}

func (p *aimPlugin) Open(context.Context) error {
	d, err := p.open()
	if err != nil {
		return err
	}
	p.dev = d
	return nil
}

func (p *aimPlugin) Presentation() plugin.Presentation { return plugin.USBTransferEndpoint }

func (p *aimPlugin) Close() error {
	if p.dev != nil {
		return p.dev.Close()
	}
	return nil
}

// Pump relays framed USB transfer requests from the guest to the device and
// writes framed responses back, one per request, until the guest closes or ctx
// is cancelled. It is transport-transparent: it forwards transfers verbatim and
// never parses the AiM payload.
func (p *aimPlugin) Pump(ctx context.Context, guest io.ReadWriteCloser) error {
	// Closing guest is the only way to unblock a pending frame read; do it when
	// ctx is cancelled so the daemon can stop this Pump.
	stop := make(chan struct{})
	defer close(stop)
	go func() {
		select {
		case <-ctx.Done():
			_ = guest.Close()
		case <-stop:
		}
	}()
	defer guest.Close()

	for {
		req, err := decodeRequest(guest)
		if err != nil {
			if cleanEnd(err, ctx) {
				return nil
			}
			return err
		}
		resp := p.issue(req)
		if err := encodeResponse(guest, resp); err != nil {
			if cleanEnd(err, ctx) {
				return nil
			}
			return err
		}
	}
}

// issue performs the device transfer for a request. A device error is surfaced
// to the guest as a non-zero status rather than tearing down the relay, matching
// the transport-transparent contract (the guest decides what a failed transfer
// means).
func (p *aimPlugin) issue(req *Request) *Response {
	var (
		in     []byte
		status int32
		err    error
	)
	switch req.Kind {
	case kindControl:
		in, status, err = p.dev.Control(req.Setup, req.Out)
	case kindBulk:
		in, status, err = p.dev.Bulk(req.Endpoint, req.Out)
	}
	if err != nil && status == 0 {
		status = -1
	}
	return &Response{Status: status, In: in}
}

// cleanEnd reports whether a read/write error is a normal end of the guest
// connection (EOF, a partial frame on disconnect, our own Close, or ctx cancel)
// rather than a real failure.
func cleanEnd(err error, ctx context.Context) bool {
	return errors.Is(err, io.EOF) ||
		errors.Is(err, io.ErrUnexpectedEOF) ||
		errors.Is(err, net.ErrClosed) ||
		errors.Is(err, os.ErrClosed) ||
		errors.Is(err, io.ErrClosedPipe) ||
		ctx.Err() != nil
}
