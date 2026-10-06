package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// inventory is what -inventory writes: the licence inventory of a framework's
// Go code, from which an app's licences list can be generated. Every module the
// checked graphs link, the main module excepted,
// with the text of each of its licence and notice files, and Go itself (its
// standard library and runtime are linked too).
type inventory struct {
	Go      inventoryModule   `json:"go"`
	Modules []inventoryModule `json:"modules"`
}

type inventoryModule struct {
	Path    string `json:"path"`
	Version string `json:"version"`
	// Replace is the go.mod replacement the module was built from (a patched copy).
	Replace  string          `json:"replace,omitempty"`
	Licenses []inventoryFile `json:"licenses"`
}

type inventoryFile struct {
	// Name is the file's path inside the module ("LICENSE", "zstd/internal/xxhash/LICENSE.txt").
	Name string `json:"name"`
	Text string `json:"text"`
}

// makeInventory lists mods (as collect returns them) and Go at goroot. The main
// module is listed only with a mainVersion: the frameworks' own bridge modules are
// ours, libXray's is not.
func makeInventory(mods map[string]*modInfo, mainVersion, goVersion, goroot string) (inventory, error) {
	text, err := os.ReadFile(filepath.Join(goroot, "LICENSE"))
	if err != nil {
		return inventory{}, fmt.Errorf("go's license: %w", err)
	}
	inv := inventory{Go: inventoryModule{
		Path: "go", Version: goVersion, Licenses: []inventoryFile{{Name: "LICENSE", Text: string(text)}},
	}}
	for _, mi := range mods {
		if mi.m.Main && mainVersion == "" {
			continue
		}
		files, err := licenseFiles(mi)
		if err != nil {
			return inventory{}, fmt.Errorf("%s: %w", mi.m.Path, err)
		}
		entry := inventoryModule{Path: mi.m.Path, Version: mi.m.Version}
		if mi.m.Main {
			entry.Version = mainVersion
		}
		if mi.m.Replace != nil {
			entry.Replace = mi.m.Replace.Path
		}
		for _, f := range files {
			b, err := os.ReadFile(f)
			if err != nil {
				return inventory{}, fmt.Errorf("%s: %w", mi.m.Path, err)
			}
			name, err := filepath.Rel(filepath.Clean(mi.dir), f)
			if err != nil {
				return inventory{}, err
			}
			entry.Licenses = append(entry.Licenses, inventoryFile{Name: filepath.ToSlash(name), Text: string(b)})
		}
		inv.Modules = append(inv.Modules, entry)
	}
	sort.Slice(inv.Modules, func(i, j int) bool { return inv.Modules[i].Path < inv.Modules[j].Path })
	return inv, nil
}

// goEnv returns GOVERSION and GOROOT of the toolchain that builds the module in dir.
func goEnv(dir string) (version, goroot string, err error) {
	cmd := exec.Command("go", "env", "GOVERSION", "GOROOT")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		return "", "", fmt.Errorf("go env: %w", err)
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) != 2 {
		return "", "", fmt.Errorf("go env: unexpected output %q", out)
	}
	return lines[0], lines[1], nil
}

func writeInventory(path, dir, mainVersion string, mods map[string]*modInfo) error {
	version, goroot, err := goEnv(dir)
	if err != nil {
		return err
	}
	inv, err := makeInventory(mods, mainVersion, version, goroot)
	if err != nil {
		return err
	}
	b, err := json.MarshalIndent(inv, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}
