import Foundation
import SceneKit
import simd

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
        // Smooth in road-local coordinates. World-space smoothing can leave the
        // camera on the wrong side of the car when the route heading changes.
        let desiredOffset = SCNVector3(lateralLag, height, distanceBack)
        let desiredLookOffset = SCNVector3(
            Float(steering) * (reduceMotion ? 0.6 : 1.8), 1.05, -(26 + speed * 8)
        )

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

        func worldOffset(_ local: SCNVector3) -> SCNVector3 {
            right * local.x + SCNVector3(0, local.y, 0) - forward * local.z
        }
        var position = carFrame.position + worldOffset(smoothedOffset)
        if shakeTime > 0 {
            shakeTime = max(0, shakeTime - deltaTime)
            let shake = shakeIntensity * Float(shakeTime / 0.28)
            position.x += sin(Float(time) * 63) * shake * 0.22
            position.y += cos(Float(time) * 47) * shake * 0.14
        }
        let lookTarget = carFrame.position + worldOffset(smoothedLookOffset)
        let lookVector = lookTarget - position
        let direction = simd_normalize(SIMD3<Float>(lookVector.x, lookVector.y, lookVector.z))
        let cameraRight = simd_normalize(simd_cross(direction, SIMD3<Float>(0, 1, 0)))
        let cameraUp = simd_cross(cameraRight, direction)
        // Set one orientation directly instead of editing Euler angles after
        // look-at; Euler decomposition changes branches around quarter turns.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        cameraNode.position = position
        cameraNode.simdOrientation = simd_quatf(simd_float3x3(columns: (cameraRight, cameraUp, -direction)))
        SCNTransaction.commit()
        currentPosition = position
        currentForward = SCNVector3(direction.x, direction.y, direction.z)

        let boostKick: CGFloat = isBoosting && !reduceMotion ? 7 : 0
        let targetFOV = baseFieldOfView + CGFloat(speed) * 6 + boostKick
        camera.fieldOfView += (targetFOV - camera.fieldOfView) * 0.08
    }
}
