// Package tray implements a system tray icon for greywall status monitoring.
package tray

import (
	"fmt"
	"os/exec"
	"runtime"
	"time"

	"github.com/GreyhavenHQ/greywall/internal/proxy"
	"fyne.io/systray"
)

const pollInterval = 10 * time.Second

// Config holds the tray configuration.
type Config struct {
	Version string
	Icon    []byte
}

// Run starts the system tray. This blocks until the tray is quit.
func Run(cfg Config) {
	c := &controller{cfg: cfg}
	systray.Run(c.onReady, c.onExit)
}

type controller struct {
	cfg        Config
	mStatus    *systray.MenuItem
	mDashboard *systray.MenuItem
	mCheck     *systray.MenuItem
	mQuit      *systray.MenuItem
}

func (c *controller) onReady() {
	// Set the tray icon. On macOS, use SetTemplateIcon for proper
	// light/dark mode adaptation.
	// NOTE: The binary must be run from within a .app bundle on macOS
	// (e.g., "open Greywall.app"), otherwise Cocoa APIs will SIGBUS.
	if len(c.cfg.Icon) > 0 {
		if runtime.GOOS == "darwin" {
			systray.SetTemplateIcon(c.cfg.Icon, c.cfg.Icon)
		} else {
			systray.SetIcon(c.cfg.Icon)
		}
	}
	systray.SetTitle("Greywall")
	systray.SetTooltip(fmt.Sprintf("Greywall %s", c.cfg.Version))

	c.mStatus = systray.AddMenuItem("Checking...", "Greyproxy status")
	c.mStatus.Disable()

	systray.AddSeparator()

	c.mDashboard = systray.AddMenuItem("Open Dashboard", "Open greyproxy dashboard in browser")
	c.mCheck = systray.AddMenuItem("Run Check", "Run greywall check")

	systray.AddSeparator()

	c.mQuit = systray.AddMenuItem("Quit", "Quit Greywall tray")

	// Initial status check
	c.updateStatus()

	// Background status poller
	go c.pollStatus()

	// Menu click handler
	go c.handleClicks()
}

func (c *controller) onExit() {
	// Cleanup if needed
}

func (c *controller) pollStatus() {
	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()
	for range ticker.C {
		c.updateStatus()
	}
}

func (c *controller) updateStatus() {
	status := proxy.Detect()
	if status.Running {
		label := "● greyproxy running"
		if status.Version != "" {
			label = fmt.Sprintf("● greyproxy running (v%s)", status.Version)
		}
		c.mStatus.SetTitle(label)
		c.mStatus.SetTooltip("Greyproxy is running and healthy")
	} else if status.Installed {
		c.mStatus.SetTitle("○ greyproxy stopped")
		c.mStatus.SetTooltip("Greyproxy is installed but not running")
	} else {
		c.mStatus.SetTitle("✗ greyproxy not installed")
		c.mStatus.SetTooltip("Greyproxy is not installed")
	}
}

func (c *controller) handleClicks() {
	for {
		select {
		case <-c.mDashboard.ClickedCh:
			openURL("http://localhost:43080")
		case <-c.mCheck.ClickedCh:
			runGreywallCheck()
		case <-c.mQuit.ClickedCh:
			systray.Quit()
			return
		}
	}
}

// openURL opens the given URL in the default browser.
func openURL(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "linux":
		cmd = exec.Command("xdg-open", url)
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", url)
	default:
		return
	}
	_ = cmd.Start()
}

// runGreywallCheck runs "greywall check" in a visible terminal.
func runGreywallCheck() {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		// Use osascript to open Terminal with the command
		script := `tell application "Terminal"
			activate
			do script "greywall check"
		end tell`
		cmd = exec.Command("osascript", "-e", script)
	case "linux":
		// Try common terminal emulators
		if _, err := exec.LookPath("gnome-terminal"); err == nil {
			cmd = exec.Command("gnome-terminal", "--", "greywall", "check")
		} else if _, err := exec.LookPath("xterm"); err == nil {
			cmd = exec.Command("xterm", "-e", "greywall", "check")
		} else {
			return
		}
	default:
		return
	}
	_ = cmd.Start()
}
