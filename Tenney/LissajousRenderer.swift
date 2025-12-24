//
//  LissajousRenderer.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/24/25.
//



//
//  LissajousRenderer.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/7/25.
//
import Foundation
import Metal
import MetalKit
import simd
import SwiftUI

final class LissajousRenderer: NSObject, MTKViewDelegate {
    // MARK: - Config
    struct Config {
        var samplesPerCurve: Int = 4096
        var strokeWidth: Float = 1.5
        var gridDivs: Int = 8
        var showGrid: Bool = true
        var showAxes: Bool = true
        var globalAlpha: Float = 1.0

        // Pro knobs
        var favorSmallIntegerClosure: Bool = true
        var maxDenSnap: Int = 24

        var dotMode: Bool = false
        var dotSize: Float = 2.0

        var persistenceEnabled: Bool = true
        var halfLifeSeconds: Float = 0.6 // phosphor decay feel
    }
    struct Ratio { var num: Int; var den: Int; var octave: Int }

    // Inputs
    var xRatio: Ratio = .init(num: 1, den: 1, octave: 0)
    var yRatio: Ratio = .init(num: 1, den: 1, octave: 0)
    var rootHz: Double = 415.0
    var theme: LatticeTheme = ThemeRegistry.theme(.classicBO, dark: false)
    var config = Config()
    
    private var needsClearPersistence = false


    // MTK
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var linePSO_MSAA: MTLRenderPipelineState!
    private var linePSO_NoMSAA: MTLRenderPipelineState!
    private var gridPSO_MSAA: MTLRenderPipelineState!
    private var gridPSO_NoMSAA: MTLRenderPipelineState!

    private var quadDecayPSO_NoMSAA: MTLRenderPipelineState!
    private var quadBlitPSO_MSAA: MTLRenderPipelineState!

    private var depth: MTLDepthStencilState!
    private var vbuf: MTLBuffer?
    private var gridBuf: MTLBuffer?
    private var uniformBuf: MTLBuffer?
    private var quadVBuf: MTLBuffer?

    // Persistence targets
    private var accumTex: MTLTexture?
    private var scratchTex: MTLTexture?
    private var linearSampler: MTLSamplerState!

    // Derived
    private var scale = SIMD2<Float>(repeating: 0.95)
    private var pan   = SIMD2<Float>(0, 0)
    private var needsRebuildCurve = true
    private var needsRebuildGrid  = true
    private var lastFrameTime = CACurrentMediaTime()

    // MARK: - Init
    init?(mtkView: MTKView) {
        guard let dev = mtkView.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        device = dev
        guard let q = device.makeCommandQueue() else { return nil }
        queue = q
        super.init()
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.sampleCount = 4
        mtkView.preferredFramesPerSecond = 60
        buildPipelines(view: mtkView)
        buildDepth()
        buildQuad()
        buildSampler()
    }

    private func buildPipelines(view: MTKView) {
        let lib = try! device.makeDefaultLibrary(bundle: .main)
        // Line / points
        let vfn = lib.makeFunction(name: "lissa_vtx")!
        let ffn = lib.makeFunction(name: "lissa_frag")!

        func makeLinePSO(sampleCount: Int) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = vfn
            d.fragmentFunction = ffn
            d.colorAttachments[0].pixelFormat = view.colorPixelFormat
            d.sampleCount = sampleCount
            d.colorAttachments[0].isBlendingEnabled = true
            d.colorAttachments[0].rgbBlendOperation = .add
            d.colorAttachments[0].alphaBlendOperation = .add
            d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            d.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try! device.makeRenderPipelineState(descriptor: d)
        }

        linePSO_MSAA   = makeLinePSO(sampleCount: view.sampleCount)
        linePSO_NoMSAA = makeLinePSO(sampleCount: 1)
        gridPSO_MSAA   = linePSO_MSAA
        gridPSO_NoMSAA = linePSO_NoMSAA

        // Quad pipelines (no MSAA)
        let qv = lib.makeFunction(name: "quad_vtx")!
        let qDecay = lib.makeFunction(name: "decay_frag")!
        let qBlit  = lib.makeFunction(name: "blit_frag")!

        func makeQuadPSO(_ frag: MTLFunction, sampleCount: Int) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = qv
            d.fragmentFunction = frag
            d.colorAttachments[0].pixelFormat = view.colorPixelFormat
            d.sampleCount = sampleCount
            d.colorAttachments[0].isBlendingEnabled = false
            return try! device.makeRenderPipelineState(descriptor: d)
        }

        quadDecayPSO_NoMSAA = makeQuadPSO(qDecay, sampleCount: 1)
        quadBlitPSO_MSAA    = makeQuadPSO(qBlit,  sampleCount: view.sampleCount)

    }

    private func buildDepth() {
        let d = MTLDepthStencilDescriptor()
        d.isDepthWriteEnabled = false
        d.depthCompareFunction = .always
        depth = device.makeDepthStencilState(descriptor: d)
    }

    private func buildQuad() {
        // 4 vertices for triangle strip
        let quad: [SIMD2<Float>] = [SIMD2(-1,-1), SIMD2(1,-1), SIMD2(-1,1), SIMD2(1,1)]
        quadVBuf = device.makeBuffer(bytes: quad, length: MemoryLayout<SIMD2<Float>>.stride * quad.count)
    }

    private func buildSampler() {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .notMipmapped
        d.sAddressMode = .clampToEdge; d.tAddressMode = .clampToEdge
        linearSampler = device.makeSamplerState(descriptor: d)
    }

    // MARK: - Curve generation
    private struct VSIn { var pos: SIMD2<Float>; var color: SIMD4<Float> }
    private struct Uniforms { var scale: SIMD2<Float>; var pan: SIMD2<Float>; var alpha: Float; var pointSize: Float }

    private func rebuildCurve() {
        needsRebuildCurve = false

        // Frequencies
        let fx = Double(xRatio.num) / Double(xRatio.den) * pow(2.0, Double(xRatio.octave)) * rootHz
        let fy = Double(yRatio.num) / Double(yRatio.den) * pow(2.0, Double(yRatio.octave)) * rootHz

        // Prefer small-integer closure if enabled
        let (px, py): (Int, Int) = {
            if config.favorSmallIntegerClosure {
                return smallIntegerApprox(fx / fy, maxDen: Int(config.maxDenSnap))
            } else {
                return smallIntegerApprox(fx / fy, maxDen: 128)
            }
        }()
        let turns = max(1, lcm(px, py))
        let base = config.dotMode ? 1 : 512
        let samples = max(base * turns, min(config.samplesPerCurve, base * turns))

        // Theme-driven color (no neon)
        func rgba(_ c: Color, alpha: CGFloat) -> SIMD4<Float> {
            #if canImport(UIKit)
            let u = UIColor(c); var r: CGFloat=0,g: CGFloat=0,b: CGFloat=0,a: CGFloat=0
            u.getRed(&r, green: &g, blue: &b, alpha: &a)
            return SIMD4(Float(r), Float(g), Float(b), Float(alpha))
            #else
            return SIMD4(1,1,1,Float(alpha))
            #endif
        }
        let stroke = rgba(theme.path, alpha: 0.95)

        // Build verts
        var verts: [VSIn] = []
        verts.reserveCapacity(samples)
        let A: Float = 1.0, B: Float = 1.0
        let twoPi = 2.0 * Double.pi
        for i in 0..<samples {
            let t = Double(i) / Double(max(1, samples-1)) * Double(turns) * twoPi
            let x = A * sin(Float(px) * Float(t))
            let y = B * sin(Float(py) * Float(t))
            verts.append(VSIn(pos: SIMD2<Float>(x, y), color: stroke))
        }
        vbuf = device.makeBuffer(bytes: verts, length: MemoryLayout<VSIn>.stride * verts.count, options: .storageModeShared)

        // Equal-aspect autoscale: fit to padded unit box
        var maxAbs: Float = 1.0
        if let ptr = vbuf?.contents().bindMemory(to: VSIn.self, capacity: verts.count) {
            for i in 0..<verts.count { maxAbs = max(maxAbs, max(abs(ptr[i].pos.x), abs(ptr[i].pos.y))) }
        }
        let s = 0.95 / maxAbs
        scale = SIMD2<Float>(repeating: s)
        writeUniforms()
    }

    private func rebuildGrid(size: CGSize) {
        needsRebuildGrid = false
        guard config.showGrid || config.showAxes else { gridBuf = nil; return }
        var lines: [VSIn] = []

        func push(_ a: SIMD2<Float>, _ b: SIMD2<Float>, color: SIMD4<Float>) {
            lines.append(VSIn(pos: a, color: color))
            lines.append(VSIn(pos: b, color: color))
        }
        func rgba(_ c: Color, _ a: CGFloat) -> SIMD4<Float> {
            #if canImport(UIKit)
            let u = UIColor(c); var r: CGFloat=0,g: CGFloat=0,b: CGFloat=0,aa: CGFloat=0
            u.getRed(&r, green: &g, blue: &b, alpha: &aa)
            return SIMD4(Float(r), Float(g), Float(b), Float(a))
            #else
            return SIMD4(1,1,1,Float(a))
            #endif
        }
        let gridC = rgba(theme.axisE3, 0.55)
        let axisC = rgba(theme.axisE5, 0.75)

        // Grid (NDC)
        if config.showGrid {
            let n = max(2, config.gridDivs)
            for i in -n...n {
                let t = Float(i) / Float(n)
                // vertical
                push(SIMD2<Float>(t, -1), SIMD2<Float>(t, 1), color: gridC)
                // horizontal
                push(SIMD2<Float>(-1, t), SIMD2<Float>(1, t), color: gridC)
            }
        }
        // Axes
        if config.showAxes {
            push(SIMD2<Float>(-1, 0), SIMD2<Float>(1, 0), color: axisC)
            push(SIMD2<Float>(0, -1), SIMD2<Float>(0, 1), color: axisC)
        }

        gridBuf = device.makeBuffer(bytes: lines, length: MemoryLayout<VSIn>.stride * lines.count, options: .storageModeShared)
    }

    private func writeUniforms() {
        var U = Uniforms(scale: scale, pan: pan, alpha: config.globalAlpha, pointSize: config.dotSize)
        if uniformBuf == nil { uniformBuf = device.makeBuffer(length: MemoryLayout<Uniforms>.stride) }
        memcpy(uniformBuf!.contents(), &U, MemoryLayout<Uniforms>.stride)
    }

    // MARK: - Persistence targets
    private func ensurePersistenceTargets(for size: CGSize, pixelFormat: MTLPixelFormat) {
        guard config.persistenceEnabled else { accumTex = nil; scratchTex = nil; return }
        let w = max(1, Int(size.width))
        let h = max(1, Int(size.height))
        func makeTex() -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            return device.makeTexture(descriptor: d)!
        }

        if accumTex == nil || accumTex!.width != w || accumTex!.height != h {
            accumTex = makeTex()
            scratchTex = makeTex()
            needsClearPersistence = true
        }

    }
    private func clearTexture(_ tex: MTLTexture, in cmd: MTLCommandBuffer) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        cmd.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
    }

    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        needsRebuildGrid = true
        ensurePersistenceTargets(for: size, pixelFormat: view.colorPixelFormat)
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = max(1.0 / Double(view.preferredFramesPerSecond), now - lastFrameTime)
        lastFrameTime = now

        if needsRebuildCurve { rebuildCurve() }
        if needsRebuildGrid  { rebuildGrid(size: view.drawableSize) }

        guard let cmd = queue.makeCommandBuffer() else { return }

        // -------- OFFSCREEN (single-sample) --------
        if config.persistenceEnabled {
            ensurePersistenceTargets(for: view.drawableSize, pixelFormat: view.colorPixelFormat)
            if needsClearPersistence, let a = accumTex, let s = scratchTex {
                clearTexture(a, in: cmd)
                clearTexture(s, in: cmd)
                needsClearPersistence = false
            }

            // (1) decay: accumTex -> scratchTex
            if let prev = accumTex, let out = scratchTex {
                let rpd = MTLRenderPassDescriptor()
                rpd.colorAttachments[0].texture = out
                rpd.colorAttachments[0].loadAction  = .dontCare
                rpd.colorAttachments[0].storeAction = .store

                let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
                enc.setRenderPipelineState(quadDecayPSO_NoMSAA)       // <— NO MSAA
                let decay = powf(0.5, Float(dt) / max(0.001, config.halfLifeSeconds))
                enc.setFragmentTexture(prev, index: 0)
                enc.setFragmentBytes([decay], length: MemoryLayout<Float>.stride, index: 0)
                enc.setFragmentSamplerState(linearSampler, index: 0)
                enc.setVertexBuffer(quadVBuf, offset: 0, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                enc.endEncoding()
            }

            // (2) draw curve into scratchTex
            if let vb = vbuf, let out = scratchTex {
                let rpd = MTLRenderPassDescriptor()
                rpd.colorAttachments[0].texture = out
                rpd.colorAttachments[0].loadAction  = .load
                rpd.colorAttachments[0].storeAction = .store

                let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
                enc.setDepthStencilState(depth)
                enc.setRenderPipelineState(linePSO_NoMSAA)            // <— NO MSAA
                writeUniforms()
                enc.setVertexBuffer(uniformBuf, offset: 0, index: 1)
                enc.setVertexBuffer(vb, offset: 0, index: 0)
                let count = vb.length / MemoryLayout<VSIn>.stride
                enc.drawPrimitives(type: config.dotMode ? .point : .lineStrip,
                                   vertexStart: 0, vertexCount: count)
                enc.endEncoding()
            }

            // (3) swap
            swap(&accumTex, &scratchTex)
        }

        // -------- SCREEN (MTKView — MSAA) --------
        guard let drawable = view.currentDrawable,
              let rpdScreen = view.currentRenderPassDescriptor else { return }

        rpdScreen.colorAttachments[0].loadAction = .clear
        rpdScreen.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        let enc = cmd.makeRenderCommandEncoder(descriptor: rpdScreen)!

        if config.persistenceEnabled, let src = accumTex {
            // (A) blit accumulated texture to screen (MSAA)
            enc.setRenderPipelineState(quadBlitPSO_MSAA)             // <— MSAA
            enc.setFragmentTexture(src, index: 0)
            enc.setFragmentSamplerState(linearSampler, index: 0)
            enc.setVertexBuffer(quadVBuf, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        } else if let vb = vbuf {
            // (A) direct draw to screen when persistence is off (MSAA)
            enc.setDepthStencilState(depth)
            enc.setRenderPipelineState(linePSO_MSAA)                 // <— MSAA
            writeUniforms()
            enc.setVertexBuffer(uniformBuf, offset: 0, index: 1)
            enc.setVertexBuffer(vb, offset: 0, index: 0)
            let count = vb.length / MemoryLayout<VSIn>.stride
            enc.drawPrimitives(type: config.dotMode ? .point : .lineStrip,
                               vertexStart: 0, vertexCount: count)
        }

        // (B) grid/axes on top (MSAA)
        if let gb = gridBuf {
            enc.setRenderPipelineState(gridPSO_MSAA)                 // <— MSAA
            enc.setVertexBuffer(uniformBuf, offset: 0, index: 1)
            enc.setVertexBuffer(gb, offset: 0, index: 0)
            let gcount = gb.length / MemoryLayout<VSIn>.stride
            enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gcount)
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Public API
    func setRatios(x: Ratio, y: Ratio, rootHz: Double) {
        self.xRatio = x; self.yRatio = y; self.rootHz = rootHz
        needsRebuildCurve = true
    }
    func setTheme(_ t: LatticeTheme) {
        theme = t
        needsRebuildGrid = true
        needsRebuildCurve = true
    }
    func setConfig(_ updater: (inout Config) -> Void) {
        updater(&config)
        needsRebuildGrid = true
        needsRebuildCurve = true
    }

    // MARK: - Utilities
    private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
    private func lcm(_ a: Int, _ b: Int) -> Int { abs(a / gcd(a,b) * b) }
    private func smallIntegerApprox(_ r: Double, maxDen: Int) -> (Int, Int) {
        var x = r, a0 = floor(x)
        var p0 = 1.0, q0 = 0.0, p1 = a0, q1 = 1.0
        while true {
            x = 1.0 / max(1e-9, (x - floor(x)))
            let a = floor(x)
            let p = a * p1 + p0
            let q = a * q1 + q0
            if q > Double(maxDen) || !p.isFinite || !q.isFinite { break }
            p0 = p1; q0 = q1; p1 = p; q1 = q
        }
        return (max(1, Int(round(p1))), max(1, Int(round(q1))))
    }
}
