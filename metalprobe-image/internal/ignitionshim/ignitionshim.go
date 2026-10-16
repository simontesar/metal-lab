// Package ignitionshim fetches the per-server Ignition document boot-operator
// serves (via the kernel-cmdline-supplied ignition.config.url) and extracts
// the raw metalprobe CLI flags string and launcher options embedded in it,
// without needing a full Ignition-spec runtime. Mirrors the pattern used by
// metal-maintenance-operator/sanitizer/config/ignitionshim.go.
package ignitionshim

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/vincent-petithory/dataurl"
)

// ConfigPath is the storage.files path metal-operator's containerlab-local
// ignition template writes the metalprobe flags string to.
const ConfigPath = "/metalprobe/config"

// IgnorePowerButtonPath is a storage.files path whose mere presence tells the
// launcher not to power off on ACPI power button events. Its contents are
// ignored. Used to simulate an OS that does not react to a graceful shutdown.
const IgnorePowerButtonPath = "/metalprobe/ignore-power-button"

// Config is the launcher configuration extracted from the Ignition document.
type Config struct {
	// Flags is the raw metalprobe CLI flags string, empty if the document
	// contains no file at ConfigPath.
	Flags string
	// IgnorePowerButton is true if the document contains a file at
	// IgnorePowerButtonPath.
	IgnorePowerButton bool
}

type ignitionDoc struct {
	Storage struct {
		Files []struct {
			Path     string `json:"path"`
			Contents struct {
				Source string `json:"source"`
			} `json:"contents"`
		} `json:"files"`
	} `json:"storage"`
}

// FetchConfig fetches the Ignition document at ignitionURL and returns the
// launcher configuration found in it: the raw metalprobe CLI flags string
// (e.g. "--registry-url=... --server-uuid=...") from the storage.files entry
// at ConfigPath and whether a file exists at IgnorePowerButtonPath.
func FetchConfig(ctx context.Context, ignitionURL string) (*Config, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ignitionURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("executing request: %w", err)
	}
	defer func() { _ = res.Body.Close() }()

	if res.StatusCode != http.StatusOK {
		data, _ := io.ReadAll(res.Body)
		return nil, fmt.Errorf("unexpected status code: %d: %s", res.StatusCode, string(data))
	}

	data, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("reading response body: %w", err)
	}

	return decodeConfig(data)
}

func decodeConfig(ignitionData []byte) (*Config, error) {
	doc := &ignitionDoc{}
	if err := json.Unmarshal(ignitionData, doc); err != nil {
		return nil, fmt.Errorf("unmarshalling json: %w", err)
	}

	cfg := &Config{}
	for _, file := range doc.Storage.Files {
		switch file.Path {
		case IgnorePowerButtonPath:
			cfg.IgnorePowerButton = true
		case ConfigPath:
			decoded, err := dataurl.DecodeString(file.Contents.Source)
			if err != nil {
				return nil, fmt.Errorf("decoding data url: %w", err)
			}
			cfg.Flags = string(decoded.Data)
		}
	}

	return cfg, nil
}
