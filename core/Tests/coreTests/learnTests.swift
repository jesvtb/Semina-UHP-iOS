import Testing
import Foundation
import MapKit
@testable import core

// @Suite("Learn tests")
// struct LearnTests {

//     @Test(
//         "MapKit GeoJSON from test case",
//         arguments: JSONTestCases.testCaseNames(inSubdirectory: "extractFeaturesDirect")
//     )
//     @MainActor
//     func testMapKitGeoJSON(testCaseName: String) throws {
//         guard let url = JSONTestCases.url(forTestCase: testCaseName, subdirectory: "extractFeaturesDirect") else {
//             struct TestCaseNotFound: Error {}
//             throw TestCaseNotFound()
//         }
//         let featureCollection = try Data(contentsOf: url)
//         let decoder = MKGeoJSONDecoder()
//         let geoJSONObjects: [MKGeoJSONObject] = try decoder.decode(featureCollection)
//         // print(type(of: geoJSONObjects))
//         print(geoJSONObjects.count)
//         print(String(describing: type(of: geoJSONObjects[0])))
//         // print(geoJSONObjects.features)

//         let fileLabel = "\(testCaseName).json"
//         try require(!geoJSONObjects.isEmpty, success: "[\(fileLabel)] Decoded GeoJSON objects", failure: "[\(fileLabel)] Expected at least 1 MKGeoJSONObject, got \(geoJSONObjects.count)")

//     }

//     @Test(
//         "Extract MKGeoJSONFeatures",
//         arguments: JSONTestCases.testCaseNames(inSubdirectory: "extractMKGeoJSONFeatures")
//     )
//     @MainActor
//     func extractMKGeoFeatures(testCaseName: String) throws {
//         guard let url = JSONTestCases.url(forTestCase: testCaseName, subdirectory: "extractMKGeoJSONFeatures") else {
//             struct TestCaseNotFound: Error {}
//             throw TestCaseNotFound()
//         }
//         let data = try Data(contentsOf: url)
//         let features = try data.extractFeatures()
//         // print(features.count)
//         print(features[0])
//         print(features[0].geometry)
//         // geometry is [MKShape & MKGeoJSONObject]; coordinate is on MKAnnotation. Get first shape and cast.
//         let coordinate: CLLocationCoordinate2D? = (features[0].geometry.first as? MKAnnotation)?.coordinate
//         print(coordinate as Any)
//         // let point = try MKPointAnnotation(feature: features[0])
//         // print(features[0].geometry?.coordinate)
//         print(features[0].properties)
//         try require(features.count == 2, success: "Expected 2 features, got \(features.count)", failure: "Expected 2 features, got \(features.count)")
//     }
// }
