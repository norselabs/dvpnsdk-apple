// Command nogpl fails when the Go code linked into one of our Go frameworks
// (LibXray, LibHysteria, WireGuardKitGo) contains GPL-family code that has not
// been reviewed, contains any github.com/sagernet module, or does not use the
// patched copies that -replace names (Xray-core and REALITY, GoBridge/).
//
// For every module in the build graphs of the Apple slices (GOOS ios and darwin,
// arm64 and amd64, -tags=<GOOS> as both build scripts pass) it scans the license
// files (module root, and every linked package directory up to the root) for
// any GNU license name, after removing the canonical MPL-2.0 text; and it scans
// every compiled file (Go, cgo, C, headers, assembly, Objective-C, syso,
// embedded files) of every module, the main module included, for a GNU license
// grant. Only modules in reviewed, at that exact version, may match.
//
//	go -C GoBridge/nogpl run . -C <module dir> [-replace <module>=<go.mod path>]... [-inventory <file>] <package>...
//
// With -inventory it also writes, once the check passes, the licence inventory
// of those graphs (inventory.go), from which the apps' licences list is made;
// -main-version lists the main module too, when it is third-party code (libXray).
//
// mpl-2.0.txt is Mozilla's text, as Xray-core ships it in its LICENSE.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// replacements are the -replace flags: module path => the go.mod replacement it must have.
type replacements map[string]string

func (r replacements) String() string { return fmt.Sprint(map[string]string(r)) }

func (r replacements) Set(v string) error {
	mod, path, ok := strings.Cut(v, "=")
	if !ok || mod == "" || path == "" {
		return fmt.Errorf("want <module>=<go.mod path>, got %q", v)
	}
	r[mod] = path
	return nil
}

type target struct{ goos, goarch string }

// The slices scripts/build-libxray.sh (through libXray's build/app/apple_go.py)
// and scripts/build-libhysteria.sh build: tvOS and the simulators are GOOS=ios,
// macOS is GOOS=darwin; each passes -tags=<GOOS>.
var targets = []target{
	{"ios", "arm64"},
	{"ios", "amd64"},
	{"darwin", "arm64"},
	{"darwin", "amd64"},
}

// Modules whose GNU-family license was reviewed by hand, pinned to the exact
// version (go.sum pins the content; a replaced module is never reviewed). None:
// the frameworks link no GNU-licensed code at all. The last one,
// github.com/juju/ratelimit (LGPL-3.0), left with the REALITY copy.
var reviewed = map[string]string{}

const bannedPrefix = "github.com/sagernet/"

type module struct {
	Path    string
	Version string
	Dir     string
	Main    bool
	Replace *module
}

type pkg struct {
	ImportPath string
	Dir        string
	Standard   bool
	Module     *module
	Error      *struct{ Err string }

	GoFiles, CgoFiles, CFiles, CXXFiles, HFiles, SFiles, MFiles, SysoFiles []string
	EmbedFiles                                                             []string
}

type modInfo struct {
	m       *module
	dir     string
	pkgDirs map[string]bool
	files   map[string]bool
	targets map[string]bool
}

var licenseName = regexp.MustCompile(`(?i)^(licen[cs]e|copying|notice|unlicense)([-._].*)?$`)

func main() {
	dir := flag.String("C", ".", "the Go module whose packages are checked")
	required := replacements{}
	flag.Var(required, "replace", "`module=path`: the go.mod replacement a module must have (a patched copy); repeatable")
	inventoryPath := flag.String("inventory", "", "write the licence inventory of the checked graphs to this `file`")
	mainVersion := flag.String("main-version", "", "list the main module in the inventory too, at this `version` (third-party code)")
	flag.Parse()
	if flag.NArg() == 0 {
		fmt.Fprintln(os.Stderr, "usage: nogpl -C <module dir> [-replace <module>=<path>]... [-inventory <file>] <package>...")
		os.Exit(2)
	}
	if err := run(os.Stdout, *dir, required, *inventoryPath, *mainVersion, flag.Args()); err != nil {
		fmt.Fprintln(os.Stderr, "nogpl:", err)
		os.Exit(1)
	}
}

func run(out io.Writer, dir string, required replacements, inventoryPath, mainVersion string, packages []string) error {
	mods, err := collect(out, dir, packages)
	if err != nil {
		return err
	}
	res := check(mods, required)
	if len(res.bad) > 0 {
		return errors.New("\n  " + strings.Join(res.bad, "\n  "))
	}
	if inventoryPath != "" {
		if err := writeInventory(inventoryPath, dir, mainVersion, mods); err != nil {
			return fmt.Errorf("inventory: %w", err)
		}
	}
	var rev, repl []string
	for k := range reviewed {
		rev = append(rev, k)
	}
	for mod, path := range required {
		repl = append(repl, mod+" => "+path)
	}
	sort.Strings(rev)
	sort.Strings(repl)
	if len(rev) == 0 {
		rev = []string{"none"}
	}
	if len(repl) == 0 {
		repl = []string{"no replacements required"}
	}
	fmt.Fprintf(out, "nogpl: ok: %d modules, %d license files, %d compiled files; no github.com/sagernet; %s; GNU-family: %s\n",
		res.modules, res.licenseFiles, res.compiledFiles, strings.Join(repl, ", "), strings.Join(rev, ", "))
	return nil
}

// collect lists every target's build graph (go list must succeed and report no
// package error) and groups the linked packages by module.
func collect(out io.Writer, dir string, packages []string) (map[string]*modInfo, error) {
	mods := map[string]*modInfo{}
	for _, t := range targets {
		name := t.goos + "/" + t.goarch
		pkgs, err := list(t, dir, packages)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		n := 0
		for _, p := range pkgs {
			if p.Error != nil {
				return nil, fmt.Errorf("%s: %s: %s", name, p.ImportPath, p.Error.Err)
			}
			if p.Standard || p.Module == nil {
				continue
			}
			key := p.Module.Path
			mi := mods[key]
			if mi == nil {
				dir := p.Module.Dir
				if p.Module.Replace != nil && p.Module.Replace.Dir != "" {
					dir = p.Module.Replace.Dir
				}
				mi = &modInfo{m: p.Module, dir: dir, pkgDirs: map[string]bool{}, files: map[string]bool{}, targets: map[string]bool{}}
				mods[key] = mi
			}
			if !mi.targets[name] {
				mi.targets[name] = true
				if !p.Module.Main {
					n++
				}
			}
			mi.pkgDirs[p.Dir] = true
			for _, list := range [][]string{p.GoFiles, p.CgoFiles, p.CFiles, p.CXXFiles, p.HFiles, p.SFiles, p.MFiles, p.SysoFiles, p.EmbedFiles} {
				for _, f := range list {
					mi.files[filepath.Join(p.Dir, f)] = true
				}
			}
		}
		fmt.Fprintf(out, "nogpl: %s: %d modules\n", name, n)
	}
	return mods, nil
}

type result struct {
	bad                                  []string
	modules, licenseFiles, compiledFiles int
}

// check applies the rules to the collected modules: every required module is
// linked as its copy, no github.com/sagernet module (by path or as a
// replacement), a license file at every dependency's root, and no GNU license
// in license files or grant in compiled files unless the module is reviewed at
// exactly that version and not replaced.
func check(mods map[string]*modInfo, required replacements) result {
	var res result
	fail := func(format string, args ...any) { res.bad = append(res.bad, fmt.Sprintf(format, args...)) }

	requiredMods := make([]string, 0, len(required))
	for mod := range required {
		requiredMods = append(requiredMods, mod)
	}
	sort.Strings(requiredMods)
	for _, mod := range requiredMods {
		path := required[mod]
		x := mods[mod]
		switch {
		case x == nil:
			fail("%s is not linked (expected the copy in %s)", mod, path)
		case x.m.Replace == nil || x.m.Replace.Path != path || x.m.Replace.Version != "":
			fail("%s must be replaced by %s in go.mod", mod, path)
		}
	}

	keys := make([]string, 0, len(mods))
	for k := range mods {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		mi := mods[k]
		where := k
		if mi.m.Version != "" {
			where += "@" + mi.m.Version
		}
		if !mi.m.Main {
			res.modules++
		}
		if strings.HasPrefix(k, bannedPrefix) {
			fail("%s is linked (github.com/sagernet is GPL-3.0)", where)
		}
		if r := mi.m.Replace; r != nil && strings.HasPrefix(r.Path, bannedPrefix) {
			fail("%s is replaced by %s (github.com/sagernet is GPL-3.0)", where, r.Path)
		}
		_, ok := reviewed[k+"@"+mi.m.Version]
		ok = ok && mi.m.Replace == nil && !mi.m.Main

		if !mi.m.Main {
			lic, err := licenseFiles(mi)
			if err != nil {
				fail("%s: %v", where, err)
			}
			for _, f := range lic {
				res.licenseFiles++
				b, err := os.ReadFile(f)
				if err != nil {
					fail("%s: %v", where, err)
					continue
				}
				if h := licenseHits(string(b)); len(h) > 0 && !ok {
					fail("%s: %s names a GNU license (%s); remove the module or review it (GoBridge/nogpl reviewed)", where, f, strings.Join(h, ", "))
				}
			}
		}
		files := make([]string, 0, len(mi.files))
		for f := range mi.files {
			files = append(files, f)
		}
		sort.Strings(files)
		for _, f := range files {
			res.compiledFiles++
			b, err := os.ReadFile(f)
			if err != nil {
				fail("%s: %v", where, err)
				continue
			}
			if bytes.IndexByte(b, 0) >= 0 && !strings.HasSuffix(f, ".go") {
				continue // binary (syso, embedded data): no license text to read
			}
			if h := grantHits(string(b)); len(h) > 0 && !ok {
				fail("%s: %s grants a GNU license (%s)", where, f, strings.Join(h, ", "))
			}
		}
	}
	return res
}

func list(t target, dir string, packages []string) ([]pkg, error) {
	args := []string{"list", "-deps", "-json=ImportPath,Dir,Standard,Module,Error,GoFiles,CgoFiles,CFiles,CXXFiles,HFiles,SFiles,MFiles,SysoFiles,EmbedFiles", "-tags=" + t.goos}
	args = append(args, packages...)
	cmd := exec.Command("go", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GOOS="+t.goos, "GOARCH="+t.goarch, "CGO_ENABLED=1", "GOFLAGS=-mod=readonly")
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("go list: %v\n%s", err, stderr.String())
	}
	var pkgs []pkg
	dec := json.NewDecoder(&stdout)
	for {
		var p pkg
		if err := dec.Decode(&p); err == io.EOF {
			break
		} else if err != nil {
			return nil, fmt.Errorf("go list output: %w", err)
		}
		pkgs = append(pkgs, p)
	}
	if len(pkgs) == 0 {
		return nil, errors.New("go list returned no packages")
	}
	return pkgs, nil
}

// licenseFiles: those in the module root (at least one is required), then
// those in each linked package directory and its parents up to the root.
func licenseFiles(mi *modInfo) ([]string, error) {
	root := filepath.Clean(mi.dir)
	if root == "." || root == "" {
		return nil, errors.New("module directory unknown (go mod download)")
	}
	seen := map[string]bool{}
	var out []string
	add := func(dir string) error {
		ents, err := os.ReadDir(dir)
		if err != nil {
			return err
		}
		for _, e := range ents {
			if !e.IsDir() && licenseName.MatchString(e.Name()) {
				f := filepath.Join(dir, e.Name())
				if !seen[f] {
					seen[f] = true
					out = append(out, f)
				}
			}
		}
		return nil
	}
	if err := add(root); err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no license file in %s", root)
	}
	for d := range mi.pkgDirs {
		for d = filepath.Clean(d); d != root && strings.HasPrefix(d, root+string(filepath.Separator)); d = filepath.Dir(d) {
			if err := add(d); err != nil {
				return nil, err
			}
		}
	}
	sort.Strings(out[1:])
	return out, nil
}
