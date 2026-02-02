//
//  geocodeTests.swift
//  coreTests
//
//  Tests for autocomplete.swift (MapSearchResult). LocationDict is in Geocoder.swift, built by Geocoder.geocodeReverse (see GeocoderTest).
//

import Testing
import Foundation
import CoreLocation
@preconcurrency import MapKit
@testable import core

struct GeocodeTests {
    // Tests for removed Geocode construction APIs were removed.
    // MapSearchResult is exercised via GeocoderTest (autocomplete) and networkingTests.
}
