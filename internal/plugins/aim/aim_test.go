package aim

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"strconv"
	"strings"
	"testing"

	"github.com/Mile-High-Ideas/marshal/internal/config"
	"github.com/Mile-High-Ideas/marshal/internal/plugin"
)

// --- frame round-trip -------------------------------------------------------

func TestFrameRoundTrip(t *testing.T) {
	reqs := []*Request{
		{Kind: kindControl, Endpoint: 0x80, Setup: Setup{BmRequestType: 0xc2, BRequest: 1, WValue: 0, WIndex: 0, WLength: 64}},
		{Kind: kindControl, Endpoint: 0x00, Setup: Setup{BmRequestType: 0x42, BRequest: 2, WValue: 0, WIndex: 3, WLength: 0}},
		{Kind: kindBulk, Endpoint: 0x01, Out: []byte("hello wheel")},
		{Kind: kindBulk, Endpoint: 0x82},
	}
	var buf bytes.Buffer
	for _, r := range reqs {
		if err := encodeRequest(&buf, r); err != nil {
			t.Fatal(err)
		}
	}
	for i, want := range reqs {
		got, err := decodeRequest(&buf)
		if err != nil {
			t.Fatalf("req %d: %v", i, err)
		}
		if got.Kind != want.Kind || got.Endpoint != want.Endpoint || got.Setup != want.Setup || !bytes.Equal(got.Out, want.Out) {
			t.Fatalf("req %d round-trip mismatch: got %+v want %+v", i, got, want)
		}
	}
	if _, err := decodeRequest(&buf); err != io.EOF {
		t.Fatalf("want EOF after last request, got %v", err)
	}

	resps := []*Response{{Status: 0, In: []byte("abc")}, {Status: -1}}
	buf.Reset()
	for _, r := range resps {
		if err := encodeResponse(&buf, r); err != nil {
			t.Fatal(err)
		}
	}
	for i, want := range resps {
		got, err := decodeResponse(&buf)
		if err != nil {
			t.Fatalf("resp %d: %v", i, err)
		}
		if got.Status != want.Status || !bytes.Equal(got.In, want.In) {
			t.Fatalf("resp %d round-trip mismatch: got %+v want %+v", i, got, want)
		}
	}
}

// --- constructor ------------------------------------------------------------

func TestNewDefaultsAndOverride(t *testing.T) {
	p, err := New(config.Device{Name: "wheel", Type: "aim-sw4"})
	if err != nil {
		t.Fatal(err)
	}
	ap := p.(*aimPlugin)
	if ap.vid != defaultVID || ap.pid != defaultPID {
		t.Fatalf("defaults: got %04x:%04x", ap.vid, ap.pid)
	}
	if p.Presentation() != plugin.USBTransferEndpoint {
		t.Fatalf("presentation: got %v", p.Presentation())
	}

	p2, err := New(config.Device{Name: "wheel", Type: "aim-sw4", USB: &config.USBConfig{VID: 0x1234, PID: 0x5678}})
	if err != nil {
		t.Fatal(err)
	}
	if ap2 := p2.(*aimPlugin); ap2.vid != 0x1234 || ap2.pid != 0x5678 {
		t.Fatalf("override: got %04x:%04x", ap2.vid, ap2.pid)
	}
}

func TestOpenWithoutHardwareBuildErrors(t *testing.T) {
	// In the default (untagged) build, openDevice is the stub → Open errors.
	p, err := New(config.Device{Name: "wheel", Type: "aim-sw4"})
	if err != nil {
		t.Fatal(err)
	}
	if err := p.Open(context.Background()); err == nil {
		t.Fatal("expected Open to error without the aim_usb build / hardware")
	}
}

// --- replay fixture ---------------------------------------------------------

type frameRec struct {
	N     int       `json:"n"`
	T     string    `json:"t"`
	EP    string    `json:"ep"`
	Dir   string    `json:"dir"`
	Setup *setupRec `json:"setup"`
	Data  string    `json:"data"`
}

type setupRec struct {
	BmRequestType uint8  `json:"bmRequestType"`
	BRequest      uint8  `json:"bRequest"`
	WValue        uint16 `json:"wValue"`
	WIndex        uint16 `json:"wIndex"`
	WLength       uint16 `json:"wLength"`
}

func loadFixture(t *testing.T) []frameRec {
	t.Helper()
	f, err := os.Open("testdata/sw4_session.ndjson.gz")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		t.Fatal(err)
	}
	defer gz.Close()
	dec := json.NewDecoder(gz)
	var recs []frameRec
	for {
		var r frameRec
		if err := dec.Decode(&r); err == io.EOF {
			break
		} else if err != nil {
			t.Fatalf("decode fixture at record %d: %v", len(recs), err)
		}
		recs = append(recs, r)
	}
	return recs
}

func parseEP(t *testing.T, s string) uint8 {
	t.Helper()
	v, err := strconv.ParseUint(strings.TrimPrefix(s, "0x"), 16, 16)
	if err != nil {
		t.Fatalf("bad ep %q: %v", s, err)
	}
	return uint8(v)
}

// mockUSB is a fixture-driven usbDevice: it returns queued IN payloads and
// records the transfers it was asked to perform, so the test can assert the
// plugin relayed each recorded transfer faithfully.
type mockUSB struct {
	bulkIn  [][]byte // queued bulk-IN payloads, popped in order
	bulkOut [][]byte // recorded bulk-OUT payloads
	ctrl    []Setup  // recorded control SETUPs
	closed  bool
}

func (m *mockUSB) Control(setup Setup, out []byte) ([]byte, int32, error) {
	m.ctrl = append(m.ctrl, setup)
	// The fixture has no control data stage, so IN returns nothing.
	return nil, 0, nil
}

func (m *mockUSB) Bulk(ep uint8, out []byte) ([]byte, int32, error) {
	if ep&0x80 != 0 { // IN
		var in []byte
		if len(m.bulkIn) > 0 {
			in = m.bulkIn[0]
			m.bulkIn = m.bulkIn[1:]
		}
		return in, 0, nil
	}
	m.bulkOut = append(m.bulkOut, append([]byte(nil), out...))
	return nil, 0, nil
}

func (m *mockUSB) Close() error { m.closed = true; return nil }

// memGuest is an in-memory ReadWriteCloser: Pump reads requests from in and
// writes responses to out.
type memGuest struct {
	in     *bytes.Reader
	out    bytes.Buffer
	closed bool
}

func (g *memGuest) Read(p []byte) (int, error)  { return g.in.Read(p) }
func (g *memGuest) Write(p []byte) (int, error) { return g.out.Write(p) }
func (g *memGuest) Close() error                { g.closed = true; return nil }

func TestReplaySessionRelaysFaithfully(t *testing.T) {
	recs := loadFixture(t)
	if len(recs) == 0 {
		t.Fatal("empty fixture")
	}

	mock := &mockUSB{}
	var reqBuf bytes.Buffer

	// Expected values, in fixture (== request) order.
	var wantCtrl []Setup
	var wantBulkOut [][]byte
	// perReq[i] = the fixture data expected back for request i (bulk-IN only), else nil.
	var perReqInWant [][]byte
	var kinds []string // "ctrlIN","ctrlOUT","bulkIN","bulkOUT" for messages

	for _, r := range recs {
		switch r.T {
		case "CTRL":
			s := Setup{}
			if r.Setup != nil {
				s = Setup{
					BmRequestType: r.Setup.BmRequestType,
					BRequest:      r.Setup.BRequest,
					WValue:        r.Setup.WValue,
					WIndex:        r.Setup.WIndex,
					WLength:       r.Setup.WLength,
				}
			}
			req := &Request{Kind: kindControl, Endpoint: parseEP(t, r.EP), Setup: s}
			if err := encodeRequest(&reqBuf, req); err != nil {
				t.Fatal(err)
			}
			wantCtrl = append(wantCtrl, s)
			perReqInWant = append(perReqInWant, nil)
			kinds = append(kinds, "ctrl")
		case "BULK":
			ep := parseEP(t, r.EP)
			data, err := hex.DecodeString(r.Data)
			if err != nil {
				t.Fatalf("frame %d: bad hex: %v", r.N, err)
			}
			if ep&0x80 != 0 { // bulk IN
				mock.bulkIn = append(mock.bulkIn, data)
				req := &Request{Kind: kindBulk, Endpoint: ep}
				if err := encodeRequest(&reqBuf, req); err != nil {
					t.Fatal(err)
				}
				perReqInWant = append(perReqInWant, data)
				kinds = append(kinds, "bulkIN")
			} else { // bulk OUT
				req := &Request{Kind: kindBulk, Endpoint: ep, Out: data}
				if err := encodeRequest(&reqBuf, req); err != nil {
					t.Fatal(err)
				}
				wantBulkOut = append(wantBulkOut, data)
				perReqInWant = append(perReqInWant, nil)
				kinds = append(kinds, "bulkOUT")
			}
		default:
			t.Fatalf("frame %d: unknown type %q", r.N, r.T)
		}
	}

	guest := &memGuest{in: bytes.NewReader(reqBuf.Bytes())}
	p := &aimPlugin{dev: mock}
	if err := p.Pump(context.Background(), guest); err != nil {
		t.Fatalf("Pump: %v", err)
	}

	// The plugin must have issued exactly the recorded control SETUPs, in order.
	if len(mock.ctrl) != len(wantCtrl) {
		t.Fatalf("control count: relayed %d, fixture %d", len(mock.ctrl), len(wantCtrl))
	}
	for i := range wantCtrl {
		if mock.ctrl[i] != wantCtrl[i] {
			t.Fatalf("control[%d] setup mismatch: relayed %+v want %+v", i, mock.ctrl[i], wantCtrl[i])
		}
	}
	// ... and forwarded exactly the recorded bulk-OUT payloads, in order.
	if len(mock.bulkOut) != len(wantBulkOut) {
		t.Fatalf("bulk-out count: relayed %d, fixture %d", len(mock.bulkOut), len(wantBulkOut))
	}
	for i := range wantBulkOut {
		if !bytes.Equal(mock.bulkOut[i], wantBulkOut[i]) {
			t.Fatalf("bulk-out[%d] payload mismatch (%d vs %d bytes)", i, len(mock.bulkOut[i]), len(wantBulkOut[i]))
		}
	}

	// One response per request, and every bulk-IN payload delivered verbatim.
	respR := bytes.NewReader(guest.out.Bytes())
	for i := range perReqInWant {
		resp, err := decodeResponse(respR)
		if err != nil {
			t.Fatalf("response %d (%s): %v", i, kinds[i], err)
		}
		if resp.Status != 0 {
			t.Fatalf("response %d (%s): status %d", i, kinds[i], resp.Status)
		}
		if want := perReqInWant[i]; want != nil && !bytes.Equal(resp.In, want) {
			t.Fatalf("response %d (%s): IN payload not relayed faithfully (%d vs %d bytes)", i, kinds[i], len(resp.In), len(want))
		}
	}
	if _, err := decodeResponse(respR); err != io.EOF {
		t.Fatalf("want exactly %d responses, found extra: %v", len(perReqInWant), err)
	}
	if !guest.closed {
		t.Fatal("Pump did not close the guest connection")
	}
}
