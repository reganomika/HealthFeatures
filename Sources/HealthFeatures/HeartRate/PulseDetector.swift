import Foundation
import QuartzCore

private let maxPeriodsToStore = 20
private let averageSize = 20
private let invalidPulsePeriod = -1
private let maxPeriod = 2.0
private let minPeriod = 0.05
private let invalidEntry: Double = -100

class PulseDetector: NSObject {
    private var upVals = [Double](repeating: 0.0, count: averageSize)
    private var downVals = [Double](repeating: 0.0, count: averageSize)
    private var upValIndex = 0
    private var downValIndex = 0
    private var lastVal: Float = 0.0
    private var periods = [Double](repeating: 0.0, count: maxPeriodsToStore)
    private var periodTimes = [Double](repeating: 0.0, count: maxPeriodsToStore)
    private var periodIndex = 0
    private var started = false
    private var freq: Float = 0.0
    private var average: Float = 0.0
    private var wasDown = false

    private var periodStart: Double = 0.0
    
    override init() {
        super.init()
        reset()
    }

    @discardableResult
    func addNewValue(newVal: Double, atTime time: Double) -> Float {
        if newVal > 0 {
            upVals[upValIndex] = newVal
            upValIndex += 1
            if upValIndex >= averageSize {
                upValIndex = 0
            }
        }
        
        if newVal < 0 {
            downVals[downValIndex] = -newVal
            downValIndex += 1
            if downValIndex >= averageSize {
                downValIndex = 0
            }
        }
        
        var count: Double = 0
        var total: Double = 0
        for i in 0..<averageSize {
            if upVals[i] != invalidEntry {
                count += 1
                total += upVals[i]
            }
        }
        
        let averageUp: Double = total/count
        count = 0
        total = 0
        for i in 0..<averageSize {
            if downVals[i] != invalidEntry {
                count += 1
                total += downVals[i]
            }
        }
        let averageDown: Double = total/count
        
        if newVal < -0.5 * averageDown {
            wasDown = true
        }
        if newVal >= 0.5 * averageUp && wasDown {
            wasDown = false
            if time - periodStart < maxPeriod && time - periodStart > minPeriod {
                periods[periodIndex] = time - periodStart
                periodTimes[periodIndex] = time
                periodIndex += 1
                if periodIndex >= maxPeriodsToStore {
                    periodIndex = 0
                }
            }
            periodStart = time
        }
        if newVal < -0.5 * averageDown {
            return -1
        } else if newVal > 0.5 * averageUp {
            return 1
        }
        return 0
    }

    func getAverage() -> Float {
        let time = CACurrentMediaTime()
        var total: Double = 0
        var count: Double = 0
        for i in 0..<maxPeriodsToStore {
            if periods[i] != invalidEntry && time - periodTimes[i] < 10 {
                count += 1
                total += periods[i]
            }
        }
        if count > 2 {
            return Float(total / count)
        }
        return Float(invalidPulsePeriod)
    }

    func reset() {
        for i in 0..<maxPeriodsToStore {
            periods[i] = invalidEntry
        }
        for i in 0..<averageSize {
            upVals[i] = invalidEntry
            downVals[i] = invalidEntry
        }
        freq = 0.5
        periodIndex = 0
        downValIndex = 0
        upValIndex = 0
    }
}
