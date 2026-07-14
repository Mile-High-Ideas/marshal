// Package bridge copies bytes bidirectionally between a guest connection and a
// device for the duration of one guest connection.
package bridge

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"sync"
)

// Pump bridges guest<->device until the guest closes, the device errors, or ctx
// is cancelled. It closes guest before returning and never closes device.
//
// The device's Read must return (0, nil) on a timeout tick so the device->guest
// loop can observe cancellation without being closed.
func Pump(ctx context.Context, guest, device io.ReadWriteCloser) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	var wg sync.WaitGroup
	errs := make([]error, 2)

	wg.Add(2)
	go func() { // guest -> device
		defer wg.Done()
		defer cancel()
		errs[0] = copyCtx(ctx, device, guest)
	}()
	go func() { // device -> guest
		defer wg.Done()
		defer cancel()
		errs[1] = copyCtx(ctx, guest, device)
	}()

	<-ctx.Done()
	_ = guest.Close() // unblock any pending guest I/O; device stays open
	wg.Wait()

	for _, e := range errs {
		if !clean(e) {
			return e
		}
	}
	return nil
}

// copyCtx copies src->dst, re-checking ctx between reads. It returns nil on EOF
// or cancellation; a (0,nil) read is a timeout tick that lets ctx be observed.
func copyCtx(ctx context.Context, dst io.Writer, src io.Reader) error {
	buf := make([]byte, 32*1024)
	for {
		if ctx.Err() != nil {
			return nil
		}
		n, rerr := src.Read(buf)
		if n > 0 {
			if _, werr := dst.Write(buf[:n]); werr != nil {
				return werr
			}
		}
		if rerr != nil {
			if errors.Is(rerr, io.EOF) {
				return nil
			}
			return rerr
		}
	}
}

// clean reports whether err is a normal teardown signal (not a real failure),
// including the errors caused by our own guest.Close().
func clean(err error) bool {
	return err == nil ||
		errors.Is(err, io.EOF) ||
		errors.Is(err, net.ErrClosed) ||
		errors.Is(err, os.ErrClosed) ||
		errors.Is(err, io.ErrClosedPipe)
}
