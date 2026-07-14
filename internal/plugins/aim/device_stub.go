//go:build !aim_usb

package aim

import "fmt"

// openDevice is the default (no-hardware) build: the gousb-backed device is
// compiled only under the aim_usb build tag, which needs libusb + pkg-config.
// The plugin's framing and relay logic — and its replay test — build and run
// without it; only claiming a real wheel requires the tagged build.
func openDevice(vid, pid uint16) (usbDevice, error) {
	return nil, fmt.Errorf("aim: USB hardware support not built into this binary "+
		"(rebuild with -tags aim_usb; requires libusb + pkg-config) for device %04x:%04x", vid, pid)
}
