package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const (
	mitText     = "MIT License\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software"
	lgplText    = "GNU LESSER GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007\n"
	gplHeading  = "GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007\n"
	grantHeader = "// This program is free software: you can redistribute it and/or modify\n" +
		"// it under the terms of the GNU General Public License as published by\n// the Free Software Foundation.\npackage x\n"
	xrayPath       = "github.com/xtls/xray-core"
	xrayReplace    = "../Xray-core"
	realityPath    = "github.com/xtls/reality"
	realityReplace = "../REALITY"
	mainModule     = "github.com/xtls/libxray"
)

// required are LibXray's -replace flags.
func required() replacements {
	return replacements{xrayPath: xrayReplace, realityPath: realityReplace}
}

// withReviewed runs the test with juju/ratelimit reviewed again, as it was until
// the REALITY copy dropped it, so the review mechanism stays tested.
func withReviewed(t *testing.T) {
	t.Helper()
	saved := reviewed
	reviewed = map[string]string{"github.com/juju/ratelimit@v1.0.2": "LGPL-3.0-only WITH LGPL-3.0-linking-exception"}
	t.Cleanup(func() { reviewed = saved })
}

// fakeModule writes files (slash paths relative to the module root) into a
// temporary module directory. Files that are not license files count as
// compiled files, and their directories as linked package directories.
func fakeModule(t *testing.T, path, version string, files map[string]string) *modInfo {
	t.Helper()
	dir := t.TempDir()
	mi := &modInfo{
		m:       &module{Path: path, Version: version, Dir: dir},
		dir:     dir,
		pkgDirs: map[string]bool{},
		files:   map[string]bool{},
		targets: map[string]bool{"ios/arm64": true},
	}
	for name, body := range files {
		f := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(f, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
		if !licenseName.MatchString(filepath.Base(f)) {
			mi.files[f] = true
			mi.pkgDirs[filepath.Dir(f)] = true
		}
	}
	return mi
}

// graph is a passing LibXray build graph: the main module, the replaced
// Xray-core and REALITY copies (MPL-2.0) and an MIT dependency.
func graph(t *testing.T) map[string]*modInfo {
	own := fakeModule(t, mainModule, "", map[string]string{
		"xray/xray.go": "// Shadowsocks 2022 is built on the GPL-3.0 sing-shadowsocks, which is not linked.\npackage xray\n",
	})
	own.m.Main = true
	xray := fakeModule(t, xrayPath, "v1.260327.1-0.20260908222543-52a412d9e2f5", map[string]string{
		"LICENSE":      mplText,
		"core/core.go": "package core\n",
	})
	xray.m.Replace = &module{Path: xrayReplace, Dir: xray.dir}
	reality := fakeModule(t, realityPath, "v0.0.0-20260908062103-8cdf7bf9c7f0", map[string]string{
		"LICENSE": "Copyright (c) 2023 RPRX. All rights reserved.\n\n" + mplText,
		"tls.go":  "package reality\n",
	})
	reality.m.Replace = &module{Path: realityReplace, Dir: reality.dir}
	mit := fakeModule(t, "example.com/mit", "v1.0.0", map[string]string{
		"LICENSE":    mitText,
		"mit.go":     "package mit\n",
		"sub/sub.go": "package sub\n",
		"sub/sub.c":  "/* SPDX-License-Identifier: MIT */\n",
	})
	return map[string]*modInfo{own.m.Path: own, xray.m.Path: xray, reality.m.Path: reality, mit.m.Path: mit}
}

func add(mods map[string]*modInfo, mi *modInfo) { mods[mi.m.Path] = mi }

func TestCheck(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func(t *testing.T, mods map[string]*modInfo)
		want   []string // substrings of the failures; none means the graph passes
	}{
		{"clean graph", func(*testing.T, map[string]*modInfo) {}, nil},
		{"sagernet module", func(t *testing.T, mods map[string]*modInfo) {
			add(mods, fakeModule(t, "github.com/sagernet/sing", "v0.5.1", map[string]string{"LICENSE": gplHeading, "sing.go": "package sing\n"}))
		}, []string{"github.com/sagernet/sing@v0.5.1 is linked", "names a GNU license"}},
		{"sagernet module even with an MIT license", func(t *testing.T, mods map[string]*modInfo) {
			add(mods, fakeModule(t, "github.com/sagernet/other", "v1.0.0", map[string]string{"LICENSE": mitText, "o.go": "package o\n"}))
		}, []string{"github.com/sagernet/other@v1.0.0 is linked"}},
		{"sagernet as a replacement", func(t *testing.T, mods map[string]*modInfo) {
			mi := fakeModule(t, "example.com/foo", "v1.0.0", map[string]string{"LICENSE": mitText, "foo.go": "package foo\n"})
			mi.m.Replace = &module{Path: "github.com/sagernet/sing", Version: "v0.5.1", Dir: mi.dir}
			add(mods, mi)
		}, []string{"is replaced by github.com/sagernet/sing"}},
		{"xray-core not linked", func(_ *testing.T, mods map[string]*modInfo) {
			delete(mods, xrayPath)
		}, []string{xrayPath + " is not linked"}},
		{"xray-core not replaced", func(_ *testing.T, mods map[string]*modInfo) {
			mods[xrayPath].m.Replace = nil
		}, []string{xrayPath + " must be replaced by " + xrayReplace}},
		{"xray-core replaced by another folder", func(_ *testing.T, mods map[string]*modInfo) {
			mods[xrayPath].m.Replace.Path = "../xray-core-upstream"
		}, []string{xrayPath + " must be replaced by " + xrayReplace}},
		{"xray-core replaced by a module version", func(_ *testing.T, mods map[string]*modInfo) {
			mods[xrayPath].m.Replace = &module{Path: xrayReplace, Version: "v1.0.0", Dir: mods[xrayPath].dir}
		}, []string{xrayPath + " must be replaced by " + xrayReplace}},
		{"REALITY not replaced", func(_ *testing.T, mods map[string]*modInfo) {
			mods[realityPath].m.Replace = nil
		}, []string{realityPath + " must be replaced by " + realityReplace}},
		{"an unreviewed LGPL module", func(t *testing.T, mods map[string]*modInfo) {
			add(mods, fakeModule(t, "github.com/juju/ratelimit", "v1.0.2", map[string]string{"LICENSE": lgplText, "ratelimit.go": "package ratelimit\n"}))
		}, []string{"github.com/juju/ratelimit@v1.0.2: ", "names a GNU license"}},
		{"dependency without a root license file", func(t *testing.T, mods map[string]*modInfo) {
			add(mods, fakeModule(t, "example.com/nolicense", "v1.0.0", map[string]string{"sub/LICENSE": mitText, "sub/x.go": "package x\n"}))
		}, []string{"example.com/nolicense@v1.0.0: no license file"}},
		{"GPL notice in a package folder of the copy", func(t *testing.T, mods map[string]*modInfo) {
			x := mods[xrayPath]
			f := filepath.Join(x.dir, "proxy", "p", "LICENSE.txt")
			if err := os.MkdirAll(filepath.Join(x.dir, "proxy", "p", "q"), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(f, []byte("This package is Licensed under the GNU General Public License v3."), 0o644); err != nil {
				t.Fatal(err)
			}
			x.pkgDirs[filepath.Join(x.dir, "proxy", "p", "q")] = true // linked below it
		}, []string{"proxy/p/LICENSE.txt names a GNU license"}},
		{"NOTICE naming a GNU license", func(t *testing.T, mods map[string]*modInfo) {
			x := mods[xrayPath]
			if err := os.WriteFile(filepath.Join(x.dir, "NOTICE"), []byte("parts are LGPL"), 0o644); err != nil {
				t.Fatal(err)
			}
		}, []string{"NOTICE names a GNU license"}},
		{"GPL grant header in the main module", func(t *testing.T, mods map[string]*modInfo) {
			m := mods[mainModule]
			f := filepath.Join(m.dir, "nodep", "nodep.go")
			if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(f, []byte(grantHeader), 0o644); err != nil {
				t.Fatal(err)
			}
			m.files[f] = true
		}, []string{"nodep/nodep.go grants a GNU license"}},
		{"GPL grant in a C file of a dependency", func(t *testing.T, mods map[string]*modInfo) {
			mit := mods["example.com/mit"]
			f := filepath.Join(mit.dir, "sub", "sub.c")
			if err := os.WriteFile(f, []byte("/* SPDX-License-Identifier: GPL-2.0-only */\n"), 0o644); err != nil {
				t.Fatal(err)
			}
		}, []string{"sub/sub.c grants a GNU license"}},
		{"NUL byte in a Go file is still scanned", func(t *testing.T, mods map[string]*modInfo) {
			mit := mods["example.com/mit"]
			if err := os.WriteFile(filepath.Join(mit.dir, "mit.go"), []byte("package mit\n\x00\n"+grantHeader), 0o644); err != nil {
				t.Fatal(err)
			}
		}, []string{"mit.go grants a GNU license"}},
		{"reviewed LGPL module at the pinned version", func(t *testing.T, mods map[string]*modInfo) {
			withReviewed(t)
			add(mods, fakeModule(t, "github.com/juju/ratelimit", "v1.0.2", map[string]string{
				"LICENSE": lgplText, "ratelimit.go": "// Licensed under the LGPLv3, see LICENCE file for details.\npackage ratelimit\n",
			}))
		}, nil},
		{"reviewed module at another version", func(t *testing.T, mods map[string]*modInfo) {
			withReviewed(t)
			add(mods, fakeModule(t, "github.com/juju/ratelimit", "v1.0.1", map[string]string{"LICENSE": lgplText, "ratelimit.go": "package ratelimit\n"}))
		}, []string{"github.com/juju/ratelimit@v1.0.1: ", "names a GNU license"}},
		{"reviewed module replaced", func(t *testing.T, mods map[string]*modInfo) {
			withReviewed(t)
			mi := fakeModule(t, "github.com/juju/ratelimit", "v1.0.2", map[string]string{"LICENSE": lgplText, "ratelimit.go": "package ratelimit\n"})
			mi.m.Replace = &module{Path: "./fork/ratelimit", Dir: mi.dir}
			add(mods, mi)
		}, []string{"github.com/juju/ratelimit@v1.0.2: ", "names a GNU license"}},
		{"unreadable compiled file", func(_ *testing.T, mods map[string]*modInfo) {
			mit := mods["example.com/mit"]
			mit.files[filepath.Join(mit.dir, "gone.go")] = true
		}, []string{"example.com/mit@v1.0.0: ", "gone.go"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			mods := graph(t)
			tc.mutate(t, mods)
			res := check(mods, required())
			if len(tc.want) == 0 {
				if len(res.bad) > 0 {
					t.Fatalf("want a pass, got:\n%s", strings.Join(res.bad, "\n"))
				}
				return
			}
			all := strings.Join(res.bad, "\n")
			for _, w := range tc.want {
				if !strings.Contains(filepath.ToSlash(all), w) {
					t.Errorf("failures do not mention %q:\n%s", w, all)
				}
			}
		})
	}
}

// Without -replace (LibHysteria) no copy is required, and the other rules still
// hold.
func TestCheckWithoutReplacements(t *testing.T) {
	mods := graph(t)
	delete(mods, xrayPath)
	delete(mods, realityPath)
	if res := check(mods, replacements{}); len(res.bad) > 0 {
		t.Fatalf("want a pass, got:\n%s", strings.Join(res.bad, "\n"))
	}
	add(mods, fakeModule(t, "github.com/sagernet/sing", "v0.5.1", map[string]string{"LICENSE": gplHeading, "sing.go": "package sing\n"}))
	if res := check(mods, replacements{}); !strings.Contains(strings.Join(res.bad, "\n"), "github.com/sagernet/sing@v0.5.1 is linked") {
		t.Fatalf("a sagernet module must fail without -replace too, got: %v", res.bad)
	}
}

func TestCheckCounts(t *testing.T) {
	res := check(graph(t), required())
	if len(res.bad) > 0 {
		t.Fatal(res.bad)
	}
	// The main module is not counted and needs no license file; xray-core,
	// REALITY and the MIT module have one LICENSE each.
	if res.modules != 3 || res.licenseFiles != 3 || res.compiledFiles != 6 {
		t.Errorf("counts: %d modules, %d license files, %d compiled files; want 3, 3, 6", res.modules, res.licenseFiles, res.compiledFiles)
	}
}

func TestReplacementFlag(t *testing.T) {
	r := replacements{}
	if err := r.Set(xrayPath + "=" + xrayReplace); err != nil || r[xrayPath] != xrayReplace {
		t.Fatalf("Set: %v, %v", err, r)
	}
	for _, bad := range []string{"", xrayPath, "=" + xrayReplace, xrayPath + "="} {
		if err := (replacements{}).Set(bad); err == nil {
			t.Errorf("Set(%q) passed", bad)
		}
	}
}

func TestInventory(t *testing.T) {
	goroot := t.TempDir()
	if err := os.WriteFile(filepath.Join(goroot, "LICENSE"), []byte("Copyright 2009 The Go Authors."), 0o644); err != nil {
		t.Fatal(err)
	}
	inv, err := makeInventory(graph(t), "", "go1.27.1", goroot)
	if err != nil {
		t.Fatal(err)
	}
	if inv.Go.Version != "go1.27.1" || len(inv.Go.Licenses) != 1 || inv.Go.Licenses[0].Text != "Copyright 2009 The Go Authors." {
		t.Errorf("go: %+v", inv.Go)
	}
	var paths []string
	for _, m := range inv.Modules {
		paths = append(paths, m.Path)
	}
	// The main module is left out; the rest are sorted by path.
	if want := []string{"example.com/mit", realityPath, xrayPath}; strings.Join(paths, " ") != strings.Join(want, " ") {
		t.Fatalf("modules %v, want %v", paths, want)
	}
	xray := inv.Modules[2]
	if xray.Replace != xrayReplace || len(xray.Licenses) != 1 || xray.Licenses[0].Name != "LICENSE" || xray.Licenses[0].Text != mplText {
		t.Errorf("xray-core: replace %q, licenses %d", xray.Replace, len(xray.Licenses))
	}
	if inv.Modules[0].Replace != "" || inv.Modules[0].Version != "v1.0.0" {
		t.Errorf("mit: %+v", inv.Modules[0])
	}
}

// With a main version the main module is listed too, with its license files.
func TestInventoryWithMainModule(t *testing.T) {
	goroot := t.TempDir()
	if err := os.WriteFile(filepath.Join(goroot, "LICENSE"), []byte("Go"), 0o644); err != nil {
		t.Fatal(err)
	}
	mods := graph(t)
	if err := os.WriteFile(filepath.Join(mods[mainModule].dir, "LICENSE"), []byte(mitText), 0o644); err != nil {
		t.Fatal(err)
	}
	inv, err := makeInventory(mods, "v26.9.9", "go1.27.1", goroot)
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range inv.Modules {
		if m.Path == mainModule {
			if m.Version != "v26.9.9" || len(m.Licenses) != 1 {
				t.Errorf("main module: %+v", m)
			}
			return
		}
	}
	t.Fatalf("the main module is not listed")
}
