package aim

import "context"

// usbDevice is the minimal libusb surface the relay needs. The real
// implementation (build tag aim_usb) wraps gousb; the replay test provides a
// fixture-driven mock. Keeping the relay behind this interface is what lets the
// plugin be built and tested with no hardware and no cgo/libusb.
//
// ctx cancellation must abort an in-flight transfer where the underlying API
// allows it, so a blocked bulk-IN (wheel idle) can't hang daemon shutdown.
type usbDevice interface {
	// Control issues a vendor control transfer described by setup. For an IN
	// transfer (setup.isIN) it returns up to setup.WLength bytes read and out is
	// ignored; for an OUT transfer it sends out. status is the libusb transfer
	// status (0 = success).
	Control(ctx context.Context, setup Setup, out []byte) (in []byte, status int32, err error)
	// Bulk issues a bulk transfer on ep. For an IN endpoint (ep&0x80 != 0) it
	// returns the bytes read and out is ignored; for an OUT endpoint it sends out.
	Bulk(ctx context.Context, ep uint8, out []byte) (in []byte, status int32, err error)
	Close() error
}
