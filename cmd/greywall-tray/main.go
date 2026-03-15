// Package main implements the greywall system tray application.
package main

import (
	_ "embed"
	"fmt"
	"os"

	"github.com/GreyhavenHQ/greywall/internal/tray"
)

// Build-time variables (set via -ldflags)
var (
	version = "dev"
)

//go:embed icon.png
var iconData []byte

func main() {
	if len(os.Args) > 1 && (os.Args[1] == "--version" || os.Args[1] == "-v") {
		fmt.Printf("greywall-tray %s\n", version)
		return
	}

	tray.Run(tray.Config{
		Version: version,
		Icon:    iconData,
	})
}
