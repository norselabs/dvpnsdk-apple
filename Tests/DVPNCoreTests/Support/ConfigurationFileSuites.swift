//
//  ConfigurationFileSuites.swift
//  DVPNSDK
//

import Testing

/// The suites that write the extensions' configuration files. One temporary directory holds them for the whole process
/// (`TemporaryConfigDirectory`), so these suites run one at a time; the others run alongside.
@Suite(.serialized)
enum ConfigurationFileSuites {}
