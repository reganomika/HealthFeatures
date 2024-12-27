import Foundation
import CoreImage
import AVFoundation
import QuartzCore

public class PulsAnalyzer: NSObject {
    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice!
    private var videoConnection: AVCaptureConnection!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let pulseDetector = PulseDetector()
    private let hueFilter = Filter()
    private var validFrameCounter = 0
    private var measurementStartedFlag = false
        
    public var startMeasurement: (() -> Void)?
    public var finishMeasurement: (() -> Void)?
    
    public func getAveragePulse() -> Float {
        let average = pulseDetector.getAverage()
        let pulse = 60.0 / average
        return pulse
    }
    
    public init(previewContainer: AVCaptureVideoPreviewLayer?) {
        super.init()
        
        videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.toggleTorch(on: true)
            }
        }
    }
    
    public func stopCapture() {
        if !captureSession.isRunning {
            return
        }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.stopRunning()
            self?.toggleTorch(on: false)
        }
    }
    
    private func toggleTorch(on: Bool) {
        guard let device = videoDevice, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Error toggling torch: \(error.localizedDescription)")
        }
    }
    
    private func process(buffer: CMSampleBuffer) {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let cameraImage = CIImage(cvPixelBuffer: pixelBuffer)

        let extent = cameraImage.extent
        let inputExtent = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)
        let averageFilter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: cameraImage, kCIInputExtentKey: inputExtent]
        )!
        let outputImage = averageFilter.outputImage!

        let ctx = CIContext(options: nil)
        guard let cgImage = ctx.createCGImage(outputImage, from: outputImage.extent) else { return }
        
        let rawData = cgImage.dataProvider!.data! as NSData
        let pixels = rawData.bytes.assumingMemoryBound(to: UInt8.self)
        let bytes = UnsafeBufferPointer(start: pixels, count: rawData.length)
        var BGRA_index = 0
        for pixel in bytes {
            switch BGRA_index {
            case 0: blue = CGFloat(pixel)
            case 1: green = CGFloat(pixel)
            case 2: red = CGFloat(pixel)
            default: break
            }
            BGRA_index += 1
        }
        
        let hsv = rgb2hsv((red: red, green: green, blue: blue, alpha: 1.0))
        if hsv.1 > 0.5 && hsv.2 > 0.5 {
       
            validFrameCounter += 1
            let filtered = hueFilter.processValue(value: Double(hsv.0))
            if validFrameCounter > 30 {
                pulseDetector.addNewValue(newVal: filtered, atTime: CACurrentMediaTime())
                
                if !measurementStartedFlag {
                    startMeasurement?()
                    measurementStartedFlag = true
                }
            }
        } else {
            validFrameCounter = 0
            measurementStartedFlag = false
            pulseDetector.reset()
            finishMeasurement?()
        }
    }
}

extension PulsAnalyzer: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        process(buffer: sampleBuffer)
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
        let fps: Int32 = 30
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
            
            activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: fps)
            activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: fps)
            unlockForConfiguration()
        }
    }
}
