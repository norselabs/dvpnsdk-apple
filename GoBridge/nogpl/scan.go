package main

import (
	_ "embed"
	"regexp"
	"strings"
)

// The canonical MPL-2.0 text. Its "Secondary License" definition names the GNU
// GPL, LGPL and AGPL, so it is removed from a license file before that file is
// scanned; anything else in the file (a copyright line, a second license) is
// still scanned.
//
//go:embed mpl-2.0.txt
var mplText string

var mplNorm = normalize(mplText)

// normalize lowercases and collapses whitespace, so notices match whatever
// their case and line wrapping.
func normalize(s string) string {
	return strings.Join(strings.Fields(strings.ToLower(s)), " ")
}

// Any mention of a GNU license family in a license file (after the MPL-2.0
// text is removed): such a module needs a review (reviewed in main.go).
var licenseMarker = regexp.MustCompile(`general public license|\b[al]?gpl|gnu\.org/licenses|\baffero\b`)

// Grants of a GNU license anywhere in a compiled file (headers, SPDX tags).
// Plain mentions ("no GPL code was used", "built on the GPL-3.0 sing") do not
// match. The text is normalized first (lowercase, single spaces).
var grantMarkers = []*regexp.Regexp{
	// SPDX tags, expressions included: "GPL-2.0-only", "MIT OR GPL-2.0-or-later",
	// "(Apache-2.0 AND LGPL-2.1-only)".
	regexp.MustCompile(`spdx-license-identifier: ?\(?([a-z0-9.+-]+\)? (or|and|with) \(?)*[a-z0-9.+-]*\b[al]?gpl`),
	// "licensed / released / distributed … under (the terms of) the GNU … License", "under the LGPL".
	regexp.MustCompile(`\b(licen[cs]ed|released|distributed|available|provided|covered) under (the )?(terms of )?(the )?(gnu )?((affero|lesser|library) )?(general public license|[al]?gpl)`),
	// "Use of this source code is governed by the GNU General Public License" / "by a GPL-3.0 license".
	regexp.MustCompile(`\bgoverned by (the |an? )?(gnu )?((affero|lesser|library) )?(general public license|[al]?gpl)`),
	// "License: GPL-3.0", "@license GPL-3.0", "licensed GPLv3", "licensed to you under the GPL".
	regexp.MustCompile(`\blicen[cs]e[ds]?:? ?(to [a-z]+ )?(under )?(the )?(gnu )?((affero|lesser|library) )?(general public license|[al]?gpl)`),
	// "This code is GPL licensed", "is LGPL-3.0-licensed".
	regexp.MustCompile(`\bis (an? )?[al]?gpl[a-z0-9.+-]*[ -]licen[cs]ed\b`),
	regexp.MustCompile(`under the terms of the gnu`),
	regexp.MustCompile(`general public license as published by`),
	regexp.MustCompile(`is free software[:;,]? you can redistribute it`),
}

// licenseHits returns the GNU-family markers in a license file.
func licenseHits(text string) []string {
	t := strings.ReplaceAll(normalize(text), mplNorm, " ")
	return uniq(licenseMarker.FindAllString(t, -1))
}

// grantHits returns the GNU license grants in a source file.
func grantHits(text string) []string {
	t := normalize(text)
	var out []string
	for _, re := range grantMarkers {
		out = append(out, re.FindAllString(t, -1)...)
	}
	return uniq(out)
}

func uniq(in []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range in {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}
