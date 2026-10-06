package main

import (
	"strings"
	"testing"
)

func TestLicenseHits(t *testing.T) {
	mit := "Permission is hereby granted, free of charge, to any person obtaining a copy of this software"
	for _, tc := range []struct {
		name string
		text string
		hit  bool
	}{
		{"MPL-2.0 canonical", mplText, false},
		{"MPL-2.0 rewrapped", strings.ReplaceAll(mplText, "\n", "\n  "), false},
		{"MPL-2.0 with copyright line", "Copyright (c) 2023 RPRX. All rights reserved.\n\n" + mplText, false},
		{"MIT", mit, false},
		{"mixed case GPL notice", "This file is licensed under the GNU General Public License v3", true},
		{"MPL plus GPL line", mplText + "\nPortions: Licensed under the GNU General Public License v3.\n", true},
		{"GPL heading", "GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007", true},
		{"LGPL heading", "GNU LESSER GENERAL PUBLIC LICENSE", true},
		{"AGPL", "GNU Affero General Public License", true},
		{"short id", "SPDX: gpl-3.0-or-later", true},
		{"LGPLv3", "licensed under the LGPLv3", true},
		{"gnu.org link", "see <https://www.gnu.org/licenses/>", true},
		{"truncated MPL", mplText[:len(mplText)/2], true},
	} {
		if got := len(licenseHits(tc.text)) > 0; got != tc.hit {
			t.Errorf("%s: hit=%v, want %v (%v)", tc.name, got, tc.hit, licenseHits(tc.text))
		}
	}
}

func TestGrantHits(t *testing.T) {
	for _, tc := range []struct {
		text string
		hit  bool
	}{
		{"// SPDX-License-Identifier: GPL-2.0-or-later\npackage x", true},
		{"// SPDX-License-Identifier: MIT OR GPL-2.0-or-later\npackage x", true},
		{"/* SPDX-License-Identifier: (Apache-2.0 AND LGPL-2.1-only) */", true},
		{"// SPDX-License-Identifier: MIT\npackage x", false},
		{"// SPDX-License-Identifier: MIT OR Apache-2.0\npackage x", false},
		{"// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\npackage x", false},
		{"// SPDX-License-Identifier: MIT\n// and the GPL-3.0 sing is not linked\npackage x", false},
		{"// Copyright 2014 Canonical Ltd.\n// Licensed under the LGPLv3 with static-linking exception.", true},
		{"// This program is free software: you can redistribute it and/or modify\n// it under the terms of the GNU General Public License as published by", true},
		{"/* distributed under the GNU Lesser General Public License */", true},
		{"// Use of this source code is governed by the GNU General Public License v3.0\n// that can be found in the LICENSE file.", true},
		{"// Use of this source code is governed by a GPL-3.0 license that can be found in the LICENSE file.", true},
		{"// Use of this source code is governed by the GNU Affero General Public License.", true},
		{"// This file is part of X, licensed GPLv3.", true},
		{"// Licensed GPL v3", true},
		{"// License: GPL-3.0", true},
		{"// @license GPL-3.0", true},
		{"// This program is licensed to you under the GPL.", true},
		{"// This code is GPL licensed.", true},
		{"// This package is LGPL-3.0-licensed.", true},
		{"// Use of this source code is governed by a BSD-style\n// license that can be found in the LICENSE file.", false},
		{"// Use of this source code is governed by an MIT-style license.", false},
		{"// License: MIT", false},
		{"// Licensed under the Apache License, Version 2.0", false},
		{"// no code of the GPL/AGPL OpenVPN implementations was used.", false},
		{"// xray-core's Shadowsocks 2022 is built on the GPL-3.0 sing-shadowsocks, which is not linked.", false},
		{"// Shadowsocks 2022 (proxy/shadowsocks_2022, built on the GPL-3.0 sing-shadowsocks)", false},
		{`return skip("shadowsocks-2022 is not supported in this build (not linked: GPL-3.0)")`, false},
		{"AddrFamilyBGPLS = 16388 // BGP-LS", false},
	} {
		if got := len(grantHits(tc.text)) > 0; got != tc.hit {
			t.Errorf("%q: hit=%v, want %v", tc.text, got, tc.hit)
		}
	}
}
