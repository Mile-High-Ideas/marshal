//go:build aim_usb

// This file is the real hardware path and is compiled only with -tags aim_usb,
// which pulls in gousb (cgo → libusb, needs pkg-config). The default build and
// the replay test do not use it.
package aim

import (
	"context"
	"fmt"

	"github.com/google/gousb"
)

// AiM SW4 endpoints (see docs/protocols/aim-sw4-usb.md §2).
const (
	bulkOutEP = 0x01
	bulkInEP  = 0x82
)

// bulkReadMax bounds a single bulk-IN transfer. §7's request framing carries no
// requested read length for bulk IN, so we read one transfer into this buffer
// and return the short-packet result. The largest transfer observed in the
// capture is ~63 KB.
const bulkReadMax = 256 * 1024

// openDevice claims the AiM SW4 over libusb and returns a transfer relay target.
func openDevice(vid, pid uint16) (usbDevice, error) {
	ctx := gousb.NewContext()
	dev, err := ctx.OpenDeviceWithVIDPID(gousb.ID(vid), gousb.ID(pid))
	if err != nil {
		ctx.Close()
		return nil, fmt.Errorf("aim: open %04x:%04x: %w", vid, pid, err)
	}
	if dev == nil {
		ctx.Close()
		return nil, fmt.Errorf("aim: device %04x:%04x not found", vid, pid)
	}
	// Detach the kernel HID driver macOS may have claimed.
	if err := dev.SetAutoDetach(true); err != nil {
		dev.Close()
		ctx.Close()
		return nil, fmt.Errorf("aim: auto-detach: %w", err)
	}
	cfg, err := dev.Config(1)
	if err != nil {
		dev.Close()
		ctx.Close()
		return nil, fmt.Errorf("aim: config 1: %w", err)
	}
	intf, err := cfg.Interface(0, 0)
	if err != nil {
		cfg.Close()
		dev.Close()
		ctx.Close()
		return nil, fmt.Errorf("aim: claim interface 0: %w", err)
	}
	// Confirm the bulk endpoints exist against the live descriptor.
	epIn, err := intf.InEndpoint(bulkInEP & 0x0f)
	if err != nil {
		intf.Close()
		cfg.Close()
		dev.Close()
		ctx.Close()
		return nil, fmt.Errorf("aim: bulk-in endpoint 0x%02x: %w", bulkInEP, err)
	}
	epOut, err := intf.OutEndpoint(bulkOutEP & 0x0f)
	if err != nil {
		intf.Close()
		cfg.Close()
		dev.Close()
		ctx.Close()
		return nil, fmt.Errorf("aim: bulk-out endpoint 0x%02x: %w", bulkOutEP, err)
	}
	return &gousbDevice{ctx: ctx, dev: dev, cfg: cfg, intf: intf, epIn: epIn, epOut: epOut}, nil
}

type gousbDevice struct {
	ctx   *gousb.Context
	dev   *gousb.Device
	cfg   *gousb.Config
	intf  *gousb.Interface
	epIn  *gousb.InEndpoint
	epOut *gousb.OutEndpoint
}

// Control issues a vendor control transfer. gousb's control transfer is not
// context-cancellable; control transfers here are short (64-byte blocks and
// zero-length triggers) so this is not a shutdown-hang risk like bulk-IN is.
func (g *gousbDevice) Control(_ context.Context, setup Setup, out []byte) ([]byte, int32, error) {
	if setup.isIN() {
		buf := make([]byte, setup.WLength)
		n, err := g.dev.Control(setup.BmRequestType, setup.BRequest, setup.WValue, setup.WIndex, buf)
		if err != nil {
			return nil, -1, err
		}
		return buf[:n], 0, nil
	}
	if _, err := g.dev.Control(setup.BmRequestType, setup.BRequest, setup.WValue, setup.WIndex, out); err != nil {
		return nil, -1, err
	}
	return nil, 0, nil
}

// Bulk issues a bulk transfer. It uses the context-aware gousb calls so a
// cancelled ctx (daemon shutdown) aborts an in-flight transfer — critical for
// bulk-IN, which blocks until the idle wheel produces data.
func (g *gousbDevice) Bulk(ctx context.Context, ep uint8, out []byte) ([]byte, int32, error) {
	if ep&0x80 != 0 {
		buf := make([]byte, bulkReadMax)
		n, err := g.epIn.ReadContext(ctx, buf)
		if err != nil {
			return nil, -1, err
		}
		return buf[:n], 0, nil
	}
	if _, err := g.epOut.WriteContext(ctx, out); err != nil {
		return nil, -1, err
	}
	return nil, 0, nil
}

func (g *gousbDevice) Close() error {
	g.intf.Close()
	err := g.cfg.Close()
	if derr := g.dev.Close(); derr != nil && err == nil {
		err = derr
	}
	if cerr := g.ctx.Close(); cerr != nil && err == nil {
		err = cerr
	}
	return err
}
