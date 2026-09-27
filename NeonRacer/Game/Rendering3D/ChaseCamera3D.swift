import Foundation
import SceneKit

@MainActor
final class ChaseCamera3D {
    let cameraNode = SCNNode()
    private let camera = SCNCamera()
    private let baseFieldOfView: CGFloat = 44
    private var shakeTime: TimeInterval = 0
    private var shakeIntensity: Float = 0
    private var smoothedOffset = SCNVector3(0, 3, 8)
    private var smoothedLookOffset = SCNVector3(0, 1, -26)
    private var hasPosition = false
    private var reduceMotion = false
    private var subjectLength: Float = 4.45
    private var subjectHeight: Float = 1.25
    private var subjectRearOverhang: Float = 2.25
    /// Camera pose after the latest update; read these instead of querying SceneKit transforms.
    private(set) var currentPosition = SCNVector3(0, 24, 110)
    private(set) var currentForward = SCNVector3(0, 0, -1)

    init() {
        camera.fieldOfView = baseFieldOfView
        camera.projectionDirection = .vertical
        camera.zNear = 0.25
        camera.zFar = 3_000
        camera.wantsHDR = true
        camera.bloomIntensity = 0.8
        camera.bloomThreshold = 0.9
        camera.bloomBlurRadius = 5
        cameraNode.name = "outrun-chase-camera"
        cameraNode.camera = camera
        cameraNode.position = currentPosition
        cameraNode.look(
            at: SCNVector3(0, 0.6, -90),
            up: SCNVector3(0, 1, 0),
            localFront: SCNVector3(0, 0, -1)
        )
    }

    func configureSubject(length: Float, height: Float, rearOverhang: Float) {
        subjectLength = max(4.0, min(length, 8.0))
        subjectHeight = max(1.0, min(height, 2.5))
        subjectRearOverhang = max(1.8, min(rearOverhang, 3.2))
        hasPosition = false
    }

    func reset() {
        hasPosition = false
        shakeTime = 0
        shakeIntensity = 0
    }

    func apply(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    func triggerShake(intensity: Double) {
        guard !reduceMotion else { return }
        shakeTime = 0.28
        shakeIntensity = Float(min(max(intensity, 0), 1))
    }

    func update(
        carFrame: TrackWorldFrame3D,
        speedRatio: Double,
        isBoosting: Bool,
        steering: Double,
        deltaTime: TimeInterval,
        time: TimeInterval
    ) {
        let forward = carFrame.forward
        let right = carFrame.right
        let speed = Float(min(max(speedRatio, 0), 1.4))
        // OutRun framing: low and close behind the car, road running to the horizon.
        let distanceBack: Float = subjectRearOverhang + 5.4 + speed * 1.4
        let height: Float = subjectHeight + 1.35 + speed * 0.25
        let lateralLag = reduceMotion ? 0 : Float(-steering) * 0.45
        var desiredOffset = right * lateralLag - forward * distanceBack
        desiredOffset.y += height
        let desiredLookOffset = forward * (26 + speed * 8)
            + right * Float(steering) * (reduceMotion ? 0.6 : 1.8)
            + SCNVector3(0, 1.05, 0)

        // Smooth offsets relative to the car so the camera never falls behind at speed.
        if !hasPosition {
            smoothedOffset = desiredOffset
            smoothedLookOffset = desiredLookOffset
            hasPosition = true
        } else {
            let rate = reduceMotion ? 5.0 : 8.0
            let smoothing = Float(1 - exp(-rate * max(deltaTime, 1.0 / 240.0)))
            smoothedOffset = smoothedOffset.lerp(to: desiredOffset, t: smoothing)
            smoothedLookOffset = smoothedLookOffset.lerp(to: desiredLookOffset, t: min(1, smoothing * 1.5))
        }

        var position = carFrame.position + smoothedOffset
        if shakeTime > 0 {
            shakeTime = max(0, shakeTime - deltaTime)
            let shake = shakeIntensity * Float(shakeTime / 0.28)
            position.x += sin(Float(time) * 63) * shake * 0.22
            position.y += cos(Float(time) * 47) * shake * 0.14
        }
        let lookTarget = carFrame.position + smoothedLookOffset
        cameraNode.position = position
        cameraNode.look(at: lookTarget, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        if !reduceMotion {
            cameraNode.eulerAngles.z += Float(-steering) * 0.03
        }

        currentPosition = position
        let lookVector = lookTarget - position
        let length = max(0.001, sqrt(lookVector.x * lookVector.x + lookVector.y * lookVector.y + lookVector.z * lookVector.z))
        currentForward = SCNVector3(lookVector.x / length, lookVector.y / length, lookVector.z / length)

        let boostKick: CGFloat = isBoosting && !reduceMotion ? 7 : 0
        let targetFOV = baseFieldOfView + CGFloat(speed) * 6 + boostKick
        camera.fieldOfView += (targetFOV - camera.fieldOfView) * 0.08
    }
}
