import SwiftUI
import MetalKit
import simd

struct IntelligenceUniverse: UIViewRepresentable {
    var phase: UniversePhase
    var level: Float
    var settings: AISettings
    var active: Bool
    var reducedMotion: Bool
    var displayScale: CGFloat
    var reportError: (String) -> Void
    func makeCoordinator() -> UniverseRenderer { UniverseRenderer() }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.backgroundColor = .black; view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.colorPixelFormat = .bgra8Unorm; view.framebufferOnly = true
        view.isAccessibilityElement = true
        view.accessibilityLabel = EchoLocalization.string("ai_universe_label")
        view.accessibilityHint = EchoLocalization.string("ai_universe_hint")
        do { try context.coordinator.install(view) }
        catch { DispatchQueue.main.async { reportError(EchoLocalization.string("ai_error_metal")) } }
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        let renderer = context.coordinator
        renderer.phase = phase; renderer.level = level; renderer.intensity = Float(settings.intensity)
        renderer.autoRotate = settings.autoRotate; renderer.reducedMotion = reducedMotion
        renderer.quality = settings.quality
        renderer.scale = min(2, displayScale)
        view.isPaused = !active
    }
    static func dismantleUIView(_ view: MTKView, coordinator: UniverseRenderer) {
        view.isPaused = true; view.delegate = nil; coordinator.release()
    }
}
final class UniverseRenderer: NSObject, MTKViewDelegate, UIGestureRecognizerDelegate {
    struct Segment { var a: SIMD4<Float>; var b: SIMD4<Float> }
    struct Uniforms {
        var transform: simd_float4x4
        var viewport: SIMD2<Float>
        var time: Float
        var level: Float
        var phase: Float
        var intensity: Float
        var motion: Float
        var padding: Float = 0
    }
    var phase = UniversePhase.idle
    var level: Float = 0
    var intensity: Float = 0.45
    var autoRotate = true
    var reducedMotion = false
    var quality = "automatic"
    var scale: CGFloat = 2
    private weak var view: MTKView?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var geometry: MTLBuffer?
    private var count = 0
    private var time: Float = 0
    private var lastTime = CACurrentMediaTime()
    private var orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var targetOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var pan = SIMD2<Float>.zero
    private var targetPan = SIMD2<Float>.zero
    private var zoom: Float = 3.8
    private var targetZoom: Float = 3.8
    private var velocity = SIMD2<Float>.zero
    private var touching = false
    private var frame = 0
    private var smoothedLevel: Float = 0
    func install(_ view: MTKView) throws {
        guard let device = view.device, let queue = device.makeCommandQueue() else { throw AIError.unavailable }
        #if SWIFT_PACKAGE
        let library = try device.makeDefaultLibrary(bundle: .module)
        #else
        let library = try device.makeDefaultLibrary(bundle: .main)
        #endif
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "echoUniverseVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "echoUniverseFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        let color = descriptor.colorAttachments[0]!
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .sourceAlpha; color.destinationRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .one
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        self.queue = queue; self.view = view
        let segments = Self.makeGeometry()
        count = segments.count
        geometry = segments.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        guard geometry != nil else { throw AIError.unavailable }
        let rotate = UIPanGestureRecognizer(target: self, action: #selector(rotate(_:)))
        rotate.maximumNumberOfTouches = 1
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panCamera(_:)))
        pan.minimumNumberOfTouches = 2; pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let roll = UIRotationGestureRecognizer(target: self, action: #selector(roll(_:)))
        let reset = UITapGestureRecognizer(target: self, action: #selector(resetCamera))
        reset.numberOfTapsRequired = 2
        for gesture in [rotate, pan, pinch, roll, reset] { gesture.delegate = self; view.addGestureRecognizer(gesture) }
        view.delegate = self; view.preferredFramesPerSecond = 60
    }
    func release() { geometry = nil; pipeline = nil; queue = nil }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc private func rotate(_ gesture: UIPanGestureRecognizer) {
        guard let view else { return }
        let delta = gesture.translation(in: view); gesture.setTranslation(.zero, in: view)
        let x = Float(delta.y) * 0.006, y = Float(delta.x) * 0.006
        targetOrientation = simd_normalize(simd_quatf(angle: y, axis: [0, 1, 0]) * simd_quatf(angle: x, axis: [1, 0, 0]) * targetOrientation)
        touching = gesture.state == .began || gesture.state == .changed
        let speed = gesture.velocity(in: view)
        velocity = touching ? .zero : SIMD2(Float(speed.y), Float(speed.x)) * 0.00005
        if reducedMotion { orientation = targetOrientation; velocity = .zero }
    }
    @objc private func panCamera(_ gesture: UIPanGestureRecognizer) {
        guard let view else { return }
        let delta = gesture.translation(in: view); gesture.setTranslation(.zero, in: view)
        targetPan += SIMD2(Float(delta.x), -Float(delta.y)) * 0.003
        targetPan = simd_clamp(targetPan, SIMD2(repeating: -1), SIMD2(repeating: 1))
        if reducedMotion { pan = targetPan }
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        targetZoom = min(6.5, max(2.3, targetZoom / Float(gesture.scale))); gesture.scale = 1
        if reducedMotion { zoom = targetZoom }
    }
    @objc private func roll(_ gesture: UIRotationGestureRecognizer) {
        targetOrientation = simd_normalize(simd_quatf(angle: -Float(gesture.rotation), axis: [0, 0, 1]) * targetOrientation)
        gesture.rotation = 0
        if reducedMotion { orientation = targetOrientation }
    }
    @objc private func resetCamera() {
        targetZoom = 3.8; targetPan = .zero; velocity = .zero
        targetOrientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        if reducedMotion { zoom = targetZoom; pan = targetPan; orientation = targetOrientation }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let pipeline, let queue, let geometry, view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }
        let now = CACurrentMediaTime(), dt = Float(min(0.05, now - lastTime)); lastTime = now
        if !reducedMotion { time += dt }
        frame += 1
        if frame % 60 == 1 {
            let constrained = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
            view.preferredFramesPerSecond = reducedMotion ? 20 : constrained || quality == "low" ? 30 : 60
            let factor: CGFloat = constrained || quality == "low" ? 1 : scale
            view.drawableSize = CGSize(width: max(1, view.bounds.width * factor), height: max(1, view.bounds.height * factor))
        }
        if !reducedMotion {
            if !touching {
                targetOrientation = simd_normalize(simd_quatf(angle: velocity.y + (autoRotate ? dt * 0.05 * intensity : 0), axis: [0, 1, 0]) * simd_quatf(angle: velocity.x, axis: [1, 0, 0]) * targetOrientation)
                velocity *= pow(0.03, dt)
            }
            orientation = simd_slerp(orientation, targetOrientation, min(1, dt * 12))
            pan += (targetPan - pan) * min(1, dt * 10); zoom += (targetZoom - zoom) * min(1, dt * 10)
        }
        smoothedLevel += (min(1, max(0, level)) - smoothedLevel) * min(1, dt * 12)
        var camera = matrix_identity_float4x4
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        camera.columns.3 = SIMD4(pan.x, pan.y, -zoom / min(1, aspect), 1)
        let f: Float = 1 / tan(0.65 / 2)
        let projection = simd_float4x4(columns: (SIMD4(f / aspect, 0, 0, 0), SIMD4(0, f, 0, 0), SIMD4(0, 0, -1.005, -1), SIMD4(0, 0, -0.1005, 0)))
        var uniforms = Uniforms(transform: projection * camera * simd_float4x4(orientation), viewport: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)), time: time, level: smoothedLevel, phase: phase.rawValue, intensity: intensity, motion: reducedMotion ? 0 : 1)
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(geometry, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        // Static buffers; one instanced draw for fine cores and soft halos together.
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
        encoder.endEncoding(); command.present(drawable); command.commit()
    }
    private static func makeGeometry() -> [Segment] {
        var seed: UInt64 = 0xEC401234
        func random() -> Float { seed = seed &* 6364136223846793005 &+ 1; return Float((seed >> 32) & 0xffff) / 65535 }
        var segments: [Segment] = []
        // Short tangent walks on concentric shells create an organic web, not latitude/longitude lines.
        for layer in 0..<8 {
            let radius: Float = layer < 3 ? 0.17 + Float(layer) * 0.09 : 0.51 + Float(layer - 3) * 0.115
            for _ in 0..<(layer < 3 ? 55 : 90) {
                var point = simd_normalize(SIMD3(random() * 2 - 1, random() * 2 - 1, random() * 2 - 1))
                var tangent = simd_normalize(simd_cross(point, SIMD3(0.31, 0.78, 0.41)))
                for _ in 0..<28 {
                    let jitter = SIMD3(random() - 0.5, random() - 0.5, random() - 0.5)
                    tangent = simd_normalize(tangent + jitter * 0.48 - point * simd_dot(point, tangent))
                    let next = simd_normalize(point + tangent * (0.016 + random() * 0.016))
                    let glow = (layer < 3 ? 0.32 : 0.22) + random() * 0.35
                    segments.append(Segment(a: SIMD4(point * radius, glow), b: SIMD4(next * (radius + (random() - 0.5) * 0.008), random() * 6.28)))
                    point = next
                }
            }
        }
        for ring in 0..<5 {
            let rotation = simd_quatf(angle: Float(ring) * 0.72 + 0.22, axis: simd_normalize(SIMD3(1, 0.2, 0.7)))
            for strand in 0..<4 {
                var previous: SIMD3<Float>?
                for step in 0...480 {
                    let angle = Float(step) / 480 * .pi * 2
                    let radius = 1.10 + Float(strand) * 0.004 + sin(angle * 29 + Float(strand)) * 0.007
                    let p = rotation.act(SIMD3(cos(angle) * radius, sin(angle) * radius, sin(angle * 41) * 0.006))
                    if let previous { segments.append(Segment(a: SIMD4(previous, 0.55), b: SIMD4(p, Float(ring)))) }
                    previous = p
                }
            }
        }
        for _ in 0..<180 {
            let p = SIMD3(random() * 3.4 - 1.7, random() * 3.4 - 1.7, random() * 2.4 - 1.2)
            segments.append(Segment(a: SIMD4(p, 0.65), b: SIMD4(p + SIMD3(0.001, 0.001, 0), random() * 6.28)))
        }
        return segments
    }
}
