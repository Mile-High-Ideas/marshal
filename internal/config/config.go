// Package config loads and validates the marshald TOML configuration.
package config

import (
	"fmt"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

// Config is the top-level daemon configuration.
type Config struct {
	Devices []Device `toml:"device"`
}

// Device describes one bridged device.
type Device struct {
	Name   string        `toml:"name"`
	Type   string        `toml:"type"`
	Socket string        `toml:"socket"`
	Serial *SerialConfig `toml:"serial"`
	USB    *USBConfig    `toml:"usb"`
}

// SerialConfig holds serial-plugin parameters.
type SerialConfig struct {
	Port string `toml:"port"`
	Baud int    `toml:"baud"`
}

// USBConfig overrides the USB vendor/product IDs for a USB-transfer plugin
// (e.g. aim-sw4). Zero values mean "use the plugin default". TOML accepts hex
// integer literals, e.g. vid = 0x11cc.
type USBConfig struct {
	VID int `toml:"vid"`
	PID int `toml:"pid"`
}

// Load reads and validates a TOML config file.
func Load(path string) (*Config, error) {
	var c Config
	if _, err := toml.DecodeFile(path, &c); err != nil {
		return nil, fmt.Errorf("config: decode %s: %w", path, err)
	}
	if err := c.Validate(); err != nil {
		return nil, err
	}
	return &c, nil
}

// Validate enforces structural rules. Unknown device types are enforced later
// by the plugin registry at daemon startup, not here.
func (c *Config) Validate() error {
	if len(c.Devices) == 0 {
		return fmt.Errorf("config: no devices defined")
	}
	names := map[string]bool{}
	sockets := map[string]bool{}
	for i, d := range c.Devices {
		if d.Name == "" {
			return fmt.Errorf("config: device #%d: empty name", i)
		}
		if d.Socket == "" {
			return fmt.Errorf("config: device %q: empty socket", d.Name)
		}
		// The socket is joined onto the runtime dir, so it must be a bare
		// filename — a path separator or "..", ".", or an absolute path could
		// place the socket outside the runtime dir.
		if d.Socket == "." || d.Socket == ".." || filepath.Base(d.Socket) != d.Socket {
			return fmt.Errorf("config: device %q: socket must be a bare filename, not a path (%q)", d.Name, d.Socket)
		}
		if names[d.Name] {
			return fmt.Errorf("config: duplicate device name %q", d.Name)
		}
		if sockets[d.Socket] {
			return fmt.Errorf("config: duplicate socket %q", d.Socket)
		}
		names[d.Name] = true
		sockets[d.Socket] = true
		if d.Type == "serial" && (d.Serial == nil || d.Serial.Port == "") {
			return fmt.Errorf("config: device %q: serial requires a port", d.Name)
		}
		if d.USB != nil {
			if d.USB.VID < 0 || d.USB.VID > 0xFFFF {
				return fmt.Errorf("config: device %q: usb vid %#x out of range (0-0xffff)", d.Name, d.USB.VID)
			}
			if d.USB.PID < 0 || d.USB.PID > 0xFFFF {
				return fmt.Errorf("config: device %q: usb pid %#x out of range (0-0xffff)", d.Name, d.USB.PID)
			}
		}
	}
	return nil
}
