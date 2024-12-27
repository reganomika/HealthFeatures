import Foundation
import AVFoundation

public enum CameraType: Int {
    case back
    case front
    
    public func captureDevice() -> AVCaptureDevice? {
        switch self {
        case .front:
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [],
                mediaType: AVMediaType.video,
                position: .front
            ).devices
            for device in devices where device.position == .front {
                return device
            }
        default:
            break
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
}

public typealias ImageBufferHandler = ((_ imageBuffer: CMSampleBuffer) -> ())

public class PulsDetector: NSObject {
    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice!
    private var videoConnection: AVCaptureConnection!
    private var audioConnection: AVCaptureConnection!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    public var imageBufferHandler: ImageBufferHandler?
    
    public init(cameraType: CameraType, previewContainer: AVCaptureVideoPreviewLayer?) {
        super.init()
        
        videoDevice = cameraType.captureDevice()
        
        do {
            captureSession.sessionPreset = .low
            videoDevice.updateVideoFormat()
        }
        
        let videoDeviceInput: AVCaptureDeviceInput
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch let error {
            fatalError("Could not create AVCaptureDeviceInput instance with error: \(error).")
        }
        guard captureSession.canAddInput(videoDeviceInput) else { fatalError() }
        captureSession.addInput(videoDeviceInput)
        
        if let previewContainer = previewContainer {
            self.previewLayer = previewContainer
            self.previewLayer?.session = captureSession
        }
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        let queue = DispatchQueue(label: "capture.queue")
        videoDataOutput.setSampleBufferDelegate(self, queue: queue)
        guard captureSession.canAddOutput(videoDataOutput) else {
            fatalError()
        }
        captureSession.addOutput(videoDataOutput)
        videoConnection = videoDataOutput.connection(with: .video)
    }
    
    public func startCapture() {
        if captureSession.isRunning {
            return
        }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    public func stopCapture() {
        if !captureSession.isRunning {
            return
        }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
}

extension PulsDetector: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if connection.videoOrientation != .portrait {
            connection.videoOrientation = .portrait
            return
        }
        if let imageBufferHandler = imageBufferHandler {
            imageBufferHandler(sampleBuffer)
        }
    }
}

public extension AVCaptureDevice {
     func availableFormatsFor(preferredFps: Float64) -> [AVCaptureDevice.Format] {
        var availableFormats: [AVCaptureDevice.Format] = []
        for format in formats
        {
            let ranges = format.videoSupportedFrameRateRanges
            for range in ranges where range.minFrameRate <= preferredFps && preferredFps <= range.maxFrameRate
            {
                availableFormats.append(format)
            }
        }
        return availableFormats
    }
    
     func formatWithHighestResolution(_ availableFormats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
        var maxWidth: Int32 = 0
        var selectedFormat: AVCaptureDevice.Format?
        for format in availableFormats {
            let desc = format.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
            let width = dimensions.width
            if width >= maxWidth {
                maxWidth = width
                selectedFormat = format
            }
        }
        return selectedFormat
    }

     func formatFor(preferredSize: CGSize, availableFormats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
        for format in availableFormats {
            let desc = format.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
            
            if dimensions.width >= Int32(preferredSize.width) && dimensions.height >= Int32(preferredSize.height) {
                return format
            }
        }
        return nil
    }
    
    func updateVideoFormat() {
        let fps = 30.0
        let availableFormats: [AVCaptureDevice.Format] = availableFormatsFor(preferredFps: Float64(fps))
        
        var selectedFormat: AVCaptureDevice.Format? = formatFor(
            preferredSize: CGSize(width: 300, height: 300),
            availableFormats: availableFormats
        )
        
        if let selectedFormat = selectedFormat {
            do {
                try lockForConfiguration()
            }
            catch let error {
                fatalError(error.localizedDescription)
            }
            activeFormat = selectedFormat
            
            activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
            activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
            unlockForConfiguration()
        }
    }
}
