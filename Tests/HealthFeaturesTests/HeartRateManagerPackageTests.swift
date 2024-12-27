import XCTest
import AVFoundation
import HealthFeatures

final class HeartRateManagerPackageTests: XCTestCase {
    func testCameraType() {
        let frontCamera = CameraType.front.captureDevice()
        XCTAssertNotNil(frontCamera, "Front camera should be available.")
        
        let backCamera = CameraType.back.captureDevice()
        XCTAssertNotNil(backCamera, "Back camera should be available.")
    }

    func testHeartRateManagerInitialization() {
        let previewLayer = AVCaptureVideoPreviewLayer()
        let manager = HeartRateManager(cameraType: .back, previewContainer: previewLayer)
        XCTAssertNotNil(manager, "HeartRateManager should be initialized correctly.")
    }
}
