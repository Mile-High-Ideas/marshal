package aim

// usbDevice is the minimal libusb surface the relay needs. The real
// implementation (build tag aim_usb) wraps gousb; the replay test provides a
// fixture-driven mock. Keeping the relay behind this interface is what lets the
// plugin be built and tested with no hardware and no cgo/libusb.
type usbDevice interface {
	// Control issues a vendor control transfer described by setup. For an IN
	// transfer (setup.isIN) it returns up to setup.WLength bytes read and out is
	// ignored; for an OUT transfer it sends out. status is the libusb transfer
	// status (0 = success).
	Control(setup Setup, out []byte) (in []byte, status int32, err error)
	// Bulk issues a bulk transfer on ep. For an IN endpoint (ep&0x80 != 0) it
	// returns the bytes read and out is ignored; for an OUT endpoint it sends out.
	Bulk(ep uint8, out []byte) (in []byte, status int32, err error)
	Close() error
}
