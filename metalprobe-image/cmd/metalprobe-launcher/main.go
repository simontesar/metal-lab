//go:build linux

// Command metalprobe-launcher runs as PID 1 in the metalprobe u-root initramfs.
// It configures networking via DHCP, fetches the metalprobe flags via Ignition,
// watches for ACPI power-button events unless Ignition asks it not to, and then
// runs metalprobe as a child process. (Metalprobe is currently not importable from out of the
// metal-operator project.) The launcher stays PID 1 and always blocks forever,
// regardless of how metalprobe exited.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/insomniacslk/dhcp/dhcpv4"
	"github.com/insomniacslk/dhcp/dhcpv6"
	"github.com/u-root/u-root/pkg/cmdline"
	"github.com/u-root/u-root/pkg/dhclient"

	"github.com/simontesar/metal-lab/metalprobe-image/internal/ignitionshim"
)

func configureDHCP(ctx context.Context) error {
	ifs, err := dhclient.Interfaces("^e.*")
	if err != nil || len(ifs) == 0 {
		allIfaces, _ := dhclient.Interfaces(".*")
		allIfaceNames := make([]string, 0, len(allIfaces))
		for _, iface := range allIfaces {
			allIfaceNames = append(allIfaceNames, fmt.Sprintf("%#+v", iface.Attrs()))
		}
		if err == nil {
			err = fmt.Errorf("no interfaces matched")
		}
		return fmt.Errorf("getting interfaces: %w (available interfaces %v)", err, allIfaceNames)
	}

	ifNames := make([]string, len(ifs))
	for i, iface := range ifs {
		ifNames[i] = iface.Attrs().Name
	}
	slog.Info("dhcp: sending requests", "interfaces", ifNames)

	var (
		errs       []error
		done       = make(chan struct{})
		closeOnce  sync.Once
		notifyDone = func() {
			closeOnce.Do(func() { close(done) })
		}
	)
	go func() {
		defer notifyDone()

		for res := range dhclient.SendRequests(ctx, ifs, true, true, dhclient.Config{
			Timeout: 15 * time.Second,
			Retries: 5,
			V4ServerAddr: &net.UDPAddr{
				IP:   net.IPv4bcast,
				Port: dhcpv4.ServerPort,
			},
			V6ServerAddr: &net.UDPAddr{
				IP:   net.ParseIP("ff02::1:2"),
				Port: dhcpv6.DefaultServerPort,
			},
		}, 30*time.Second) {
			if res.Err != nil {
				errs = append(errs, res.Err)
				continue
			}

			if err := res.Lease.Configure(); err != nil {
				errs = append(errs, err)
				continue
			}

			notifyDone()
		}
	}()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-done:
		return errors.Join(errs...)
	}
}

func main() {
	ctx := context.Background()

	ignitionURL, _ := cmdline.Flag("ignition.config.url")
	if ignitionURL == "" {
		go watchACPIPowerButton()
		park(fmt.Errorf("no ignition.config.url on kernel cmdline"))
	}

	cfg, err := ignitionshim.FetchConfig(ctx, ignitionURL)
	if err != nil {
		go watchACPIPowerButton()
		park(fmt.Errorf("fetching metalprobe config: %w", err))
	}

	if cfg.IgnorePowerButton {
		slog.Info("acpi: ignoring power button as requested by ignition", "path", ignitionshim.IgnorePowerButtonPath)
	} else {
		go watchACPIPowerButton()
	}

	// Images booted for a ServerClaim usually carry no metalprobe config and
	// only need to stay up, so this is not an error.
	if cfg.Flags == "" {
		slog.Info("not running metalprobe, no config in ignition", "path", ignitionshim.ConfigPath)
		park(nil)
		select {}
	}

	args := strings.Fields(cfg.Flags)
	slog.Info("starting metalprobe", "args", args)

	cmd := exec.Command("metalprobe", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		park(fmt.Errorf("metalprobe exited: %w", err))
	}
	slog.Info("metalprobe ran successfully")

	park(nil)
}

// park blocks forever so that PID 1 does not return.
func park(err error) {
	if err != nil {
		slog.Error("metalprobe-launcher parking after error", "error", err)
	} else {
		slog.Info("metalprobe-launcher parking")
	}
	select {}
}
