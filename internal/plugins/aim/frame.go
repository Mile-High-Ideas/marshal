// Package aim bridges an AiM SW4 steering wheel (USB VID 0x11CC / PID 0x0110) to
// a guest app as a transport-transparent USB transfer relay: the guest sends
// framed control/bulk transfer requests and receives framed responses. The
// plugin never parses the AiM payload. See docs/protocols/aim-sw4-usb.md.
package aim

import (
	"encoding/binary"
	"fmt"
	"io"
)

// Request kinds (design spec §7).
const (
	kindControl uint8 = 1
	kindBulk    uint8 = 2
)

// maxTransfer caps a single relayed transfer to guard against a corrupt or
// hostile length field. The real capture's largest transfer is ~63 KB.
const maxTransfer = 1 << 20 // 1 MiB

// Setup is the 8-byte USB control SETUP packet.
type Setup struct {
	BmRequestType uint8
	BRequest      uint8
	WValue        uint16
	WIndex        uint16
	WLength       uint16
}

// isIN reports whether the control transfer's data stage is device→host.
func (s Setup) isIN() bool { return s.BmRequestType&0x80 != 0 }

// Request is one guest→host transfer request (design spec §7).
type Request struct {
	Kind     uint8
	Endpoint uint8
	Setup    Setup  // meaningful when Kind == kindControl
	Out      []byte // OUT payload; empty for IN transfers
}

// Response is one host→guest transfer response (design spec §7).
type Response struct {
	Status int32 // 0 = success
	In     []byte
}

// decodeRequest reads a single request frame. It returns io.EOF when the guest
// closes cleanly between frames.
func decodeRequest(r io.Reader) (*Request, error) {
	var hdr [4]byte // kind, endpoint, u16 reserved
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return nil, err
	}
	req := &Request{Kind: hdr[0], Endpoint: hdr[1]}
	switch req.Kind {
	case kindControl:
		var s [8]byte
		if _, err := io.ReadFull(r, s[:]); err != nil {
			return nil, err
		}
		req.Setup = Setup{
			BmRequestType: s[0],
			BRequest:      s[1],
			WValue:        binary.LittleEndian.Uint16(s[2:4]),
			WIndex:        binary.LittleEndian.Uint16(s[4:6]),
			WLength:       binary.LittleEndian.Uint16(s[6:8]),
		}
	case kindBulk:
		// no setup
	default:
		return nil, fmt.Errorf("aim: unknown request kind %d", req.Kind)
	}
	var lenb [4]byte
	if _, err := io.ReadFull(r, lenb[:]); err != nil {
		return nil, err
	}
	outLen := binary.LittleEndian.Uint32(lenb[:])
	if outLen > maxTransfer {
		return nil, fmt.Errorf("aim: out length %d exceeds max %d", outLen, maxTransfer)
	}
	if outLen > 0 {
		req.Out = make([]byte, outLen)
		if _, err := io.ReadFull(r, req.Out); err != nil {
			return nil, err
		}
	}
	return req, nil
}

// encodeResponse writes a single response frame (the host/plugin side).
func encodeResponse(w io.Writer, resp *Response) error {
	var head [8]byte
	binary.LittleEndian.PutUint32(head[0:4], uint32(resp.Status))
	binary.LittleEndian.PutUint32(head[4:8], uint32(len(resp.In)))
	if _, err := w.Write(head[:]); err != nil {
		return err
	}
	if len(resp.In) > 0 {
		if _, err := w.Write(resp.In); err != nil {
			return err
		}
	}
	return nil
}
