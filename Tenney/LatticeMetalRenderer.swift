//
//  LatticeMetalRenderer.swift
//  Tenney
//

import Foundation
import Metal
import MetalKit
import QuartzCore
#if canImport(MetalFX)
import MetalFX
#endif

final class LatticeMetalRenderer: NSObject, MTKViewDelegate {
    struct Diagnostics {
        var lastCPUEncodeMs: Double = 0
        var lastGPUTimeMs: Double = 0
        var lastVisibleCount: Int = 0
        var lastPickLatencyFrames: Int = 0
    }

    struct Buffers {
        let nodeBuffer: MTLBuffer
        let linkBuffer: MTLBuffer
        let visibleIndexBuffer: MTLBuffer
        let visibleCountBuffer: MTLBuffer
        let screenNodeBuffer: MTLBuffer
        let uniformBuffer: MTLBuffer
        let indirectArgsBuffer: MTLBuffer
        let pickBuffer: MTLBuffer
        let quadVertexBuffer: MTLBuffer
        let quadIndexBuffer: MTLBuffer
        let linkVertexBuffer: MTLBuffer
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let maxNodes = 2048
    private let maxLinks = 4096
    private let buffers: Buffers

    private let puckPipeline: MTLRenderPipelineState
    private let linkPipeline: MTLRenderPipelineState
    private let cullPipeline: MTLComputePipelineState
    private let indirectPipeline: MTLComputePipelineState
    private let pickPipeline: MTLComputePipelineState

    private var snapshot: LatticeMetalSnapshot?
    private let snapshotLock = NSLock()

    private var pendingPick: LatticeMetalPickRequest?
    private let pickLock = NSLock()
    private var frameIndex: Int = 0
    private var lastPickToken: UInt32 = 0
    private var diagnostics = Diagnostics()

    private var useMetalFX = true
    private var metalFXScaler: Any?
    private var metalFXInputTexture: MTLTexture?
    private var metalFXOutputTexture: MTLTexture?
    private var metalFXSupported = true
    private var lastFXInputWidth: Int?
    private var lastFXInputHeight: Int?
    private var lastFXOutputWidth: Int?
    private var lastFXOutputHeight: Int?
    private var lastFXPixelFormat: MTLPixelFormat?
    private var lastIndirectArgsLogTime: CFTimeInterval = 0

    var onPick: ((LatticeMetalPickResult) -> Void)?

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.commandQueue = commandQueue

        let nodeBuffer = device.makeBuffer(length: MemoryLayout<LatticeMetalNode>.stride * maxNodes, options: .storageModeShared)
        let linkBuffer = device.makeBuffer(length: MemoryLayout<LatticeMetalLink>.stride * maxLinks, options: .storageModeShared)
        let visibleIndexBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride * maxNodes, options: .storageModeShared)
        let visibleCountBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        let screenNodeBuffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * maxNodes, options: .storageModeShared)
        let uniformBuffer = device.makeBuffer(length: MemoryLayout<LatticeMetalUniforms>.stride * 3, options: .storageModeShared)
        let indirectArgsBuffer = device.makeBuffer(length: MemoryLayout<MTLDrawIndexedPrimitivesIndirectArguments>.stride, options: .storageModeShared)
        let pickBuffer = device.makeBuffer(length: MemoryLayout<LatticeMetalPickResult>.stride, options: .storageModeShared)

        let quadVertices: [SIMD2<Float>] = [
            SIMD2(-0.5, -0.5),
            SIMD2(0.5, -0.5),
            SIMD2(0.5, 0.5),
            SIMD2(-0.5, 0.5)
        ]
        let quadVertexBuffer = device.makeBuffer(bytes: quadVertices, length: MemoryLayout<SIMD2<Float>>.stride * quadVertices.count, options: .storageModeShared)
        let quadIndices: [UInt16] = [0, 1, 2, 0, 2, 3]
        let quadIndexBuffer = device.makeBuffer(bytes: quadIndices, length: MemoryLayout<UInt16>.stride * quadIndices.count, options: .storageModeShared)

        let linkVertices: [SIMD2<Float>] = [
            SIMD2(-0.5, -1.0),
            SIMD2(0.5, -1.0),
            SIMD2(0.5, 1.0),
            SIMD2(-0.5, -1.0),
            SIMD2(0.5, 1.0),
            SIMD2(-0.5, 1.0)
        ]
        let linkVertexBuffer = device.makeBuffer(bytes: linkVertices, length: MemoryLayout<SIMD2<Float>>.stride * linkVertices.count, options: .storageModeShared)

        guard let nodeBuffer,
              let linkBuffer,
              let visibleIndexBuffer,
              let visibleCountBuffer,
              let screenNodeBuffer,
              let uniformBuffer,
              let indirectArgsBuffer,
              let pickBuffer,
              let quadVertexBuffer,
              let quadIndexBuffer,
              let linkVertexBuffer
        else {
            return nil
        }

        buffers = Buffers(
            nodeBuffer: nodeBuffer,
            linkBuffer: linkBuffer,
            visibleIndexBuffer: visibleIndexBuffer,
            visibleCountBuffer: visibleCountBuffer,
            screenNodeBuffer: screenNodeBuffer,
            uniformBuffer: uniformBuffer,
            indirectArgsBuffer: indirectArgsBuffer,
            pickBuffer: pickBuffer,
            quadVertexBuffer: quadVertexBuffer,
            quadIndexBuffer: quadIndexBuffer,
            linkVertexBuffer: linkVertexBuffer
        )

        guard let library = device.makeDefaultLibrary() else { return nil }

        let puckDescriptor = MTLRenderPipelineDescriptor()
        puckDescriptor.vertexFunction = library.makeFunction(name: "puckVertex")
        puckDescriptor.fragmentFunction = library.makeFunction(name: "puckFragment")
        puckDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        puckDescriptor.colorAttachments[0].isBlendingEnabled = true
        puckDescriptor.colorAttachments[0].rgbBlendOperation = .add
        puckDescriptor.colorAttachments[0].alphaBlendOperation = .add
        puckDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        puckDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        puckDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        puckDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let linkDescriptor = MTLRenderPipelineDescriptor()
        linkDescriptor.vertexFunction = library.makeFunction(name: "linkVertex")
        linkDescriptor.fragmentFunction = library.makeFunction(name: "linkFragment")
        linkDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        linkDescriptor.colorAttachments[0].isBlendingEnabled = true
        linkDescriptor.colorAttachments[0].rgbBlendOperation = .add
        linkDescriptor.colorAttachments[0].alphaBlendOperation = .add
        linkDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        linkDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        linkDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        linkDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let puckPipeline = try? device.makeRenderPipelineState(descriptor: puckDescriptor),
              let linkPipeline = try? device.makeRenderPipelineState(descriptor: linkDescriptor),
              let cullPipeline = library.makeFunction(name: "cullNodes").flatMap({ try? device.makeComputePipelineState(function: $0) }),
              let indirectPipeline = library.makeFunction(name: "buildIndirectArgs").flatMap({ try? device.makeComputePipelineState(function: $0) }),
              let pickPipeline = library.makeFunction(name: "pickNodes").flatMap({ try? device.makeComputePipelineState(function: $0) })
        else { return nil }

        self.puckPipeline = puckPipeline
        self.linkPipeline = linkPipeline
        self.cullPipeline = cullPipeline
        self.indirectPipeline = indirectPipeline
        self.pickPipeline = pickPipeline
        super.init()
    }

    func update(snapshot: LatticeMetalSnapshot) {
        snapshotLock.lock()
        self.snapshot = snapshot
        snapshotLock.unlock()
        let wasUsingMetalFX = useMetalFX
        useMetalFX = snapshot.useMetalFX
        if useMetalFX && !wasUsingMetalFX {
            metalFXSupported = true
        }
    }

    func enqueuePick(_ request: LatticeMetalPickRequest) {
        pickLock.lock()
        if request.token != lastPickToken {
            pendingPick = request
            lastPickToken = request.token
        }
        pickLock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        snapshotLock.lock()
        if var snapshot = snapshot {
            snapshot.viewSize = size
            self.snapshot = snapshot
        }
        snapshotLock.unlock()
        rebuildMetalFXIfNeeded(view: view, drawableSize: size)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }

        snapshotLock.lock()
        guard var snapshot = snapshot else {
            snapshotLock.unlock()
            return
        }
        snapshotLock.unlock()

        let nodeCount = min(snapshot.nodes.count, maxNodes)
        let linkCount = min(snapshot.links.count, maxLinks)

        if nodeCount > 0 {
            snapshot.nodes.withUnsafeBytes { bytes in
                let size = MemoryLayout<LatticeMetalNode>.stride * nodeCount
                buffers.nodeBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: size)
            }
        }
        if linkCount > 0 {
            snapshot.links.withUnsafeBytes { bytes in
                let size = MemoryLayout<LatticeMetalLink>.stride * linkCount
                buffers.linkBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: size)
            }
        }

        frameIndex &+= 1
        let currentFrame = frameIndex
        let uniformIndex = frameIndex % 3
        let uniformPointer = buffers.uniformBuffer.contents().advanced(by: MemoryLayout<LatticeMetalUniforms>.stride * uniformIndex)
        var uniforms = LatticeMetalUniforms(
            viewportSize: SIMD2(Float(snapshot.viewSize.width), Float(snapshot.viewSize.height)),
            translation: SIMD2(Float(snapshot.camera.translation.x), Float(snapshot.camera.translation.y)),
            scale: Float(snapshot.camera.appliedScale),
            baseRadius: snapshot.baseRadius,
            time: Float(snapshot.time),
            audioAmplitude: snapshot.audioAmplitude,
            audioPhase: snapshot.audioPhase,
            debugFlags: snapshot.debugFlags,
            linkAlpha: snapshot.linkAlpha,
            hoverLift: snapshot.hoverLift
        )
        uniformPointer.copyMemory(from: &uniforms, byteCount: MemoryLayout<LatticeMetalUniforms>.stride)

        let cpuStart = CACurrentMediaTime()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.fill(buffer: buffers.visibleCountBuffer, range: 0..<MemoryLayout<UInt32>.stride, value: 0)
            blit.endEncoding()
        }

        if nodeCount > 0, let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setComputePipelineState(cullPipeline)
            compute.setBuffer(buffers.nodeBuffer, offset: 0, index: 0)
            compute.setBuffer(buffers.visibleIndexBuffer, offset: 0, index: 1)
            compute.setBuffer(buffers.visibleCountBuffer, offset: 0, index: 2)
            compute.setBuffer(buffers.screenNodeBuffer, offset: 0, index: 3)
            var nodeCountValue = UInt32(nodeCount)
            compute.setBytes(&nodeCountValue, length: MemoryLayout<UInt32>.stride, index: 4)
            compute.setBuffer(buffers.uniformBuffer, offset: MemoryLayout<LatticeMetalUniforms>.stride * uniformIndex, index: 5)

            let w = cullPipeline.threadExecutionWidth
            let threads = MTLSize(width: nodeCount, height: 1, depth: 1)
            let threadsPerGroup = MTLSize(width: max(1, w), height: 1, depth: 1)
            compute.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
            compute.endEncoding()
        }

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setComputePipelineState(indirectPipeline)
            compute.setBuffer(buffers.visibleCountBuffer, offset: 0, index: 0)
            compute.setBuffer(buffers.indirectArgsBuffer, offset: 0, index: 1)
            var indexCount = UInt32(6)
            compute.setBytes(&indexCount, length: MemoryLayout<UInt32>.stride, index: 2)
            compute.endEncoding()
        }

        pickLock.lock()
        let pickRequest = pendingPick
        pendingPick = nil
        pickLock.unlock()

        let pickToken = pickRequest?.token
        let pickRequestFrame = pickRequest == nil ? nil : currentFrame
        if var pickRequest, nodeCount > 0, let compute = commandBuffer.makeComputeCommandEncoder() {
            let invalidPick = LatticeMetalPickResult(nodeID: UInt32.max, distanceSquared: UInt32.max, kind: pickRequest.kind, token: pickRequest.token)
            withUnsafeBytes(of: invalidPick) { bytes in
                buffers.pickBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: MemoryLayout<LatticeMetalPickResult>.stride)
            }
            compute.setComputePipelineState(pickPipeline)
            compute.setBuffer(buffers.visibleIndexBuffer, offset: 0, index: 0)
            compute.setBuffer(buffers.visibleCountBuffer, offset: 0, index: 1)
            compute.setBuffer(buffers.screenNodeBuffer, offset: 0, index: 2)
            compute.setBuffer(buffers.nodeBuffer, offset: 0, index: 3)
            compute.setBytes(&pickRequest, length: MemoryLayout<LatticeMetalPickRequest>.stride, index: 4)
            compute.setBuffer(buffers.pickBuffer, offset: 0, index: 5)

            let w = pickPipeline.threadExecutionWidth
            let threads = MTLSize(width: nodeCount, height: 1, depth: 1)
            let threadsPerGroup = MTLSize(width: max(1, w), height: 1, depth: 1)
            compute.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
            compute.endEncoding()
        }

        if useMetalFX, metalFXInputTexture == nil {
            rebuildMetalFXIfNeeded(view: view, drawableSize: view.drawableSize)
        }

        let renderTarget: MTLTexture
#if canImport(MetalFX)
        let canUseMetalFX = useMetalFX && metalFXInputTexture != nil && (metalFXScaler as? any MTLFXSpatialScaler) != nil
#else
        let canUseMetalFX = false
#endif
        if canUseMetalFX, let metalFXTexture = metalFXInputTexture {
            renderTarget = metalFXTexture
        } else {
            renderTarget = drawable.texture
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        guard let colorAttachment = renderPassDescriptor.colorAttachments[0] else { return }
        colorAttachment.texture = renderTarget
        colorAttachment.loadAction = .clear
        colorAttachment.storeAction = .store
#if DEBUG
        if snapshot.debugFlags != 0 {
            colorAttachment.clearColor = canUseMetalFX
                ? MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)
                : MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1)
        } else {
            colorAttachment.clearColor = view.clearColor
        }
#else
        colorAttachment.clearColor = view.clearColor
#endif

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            if linkCount > 0 {
                encoder.setRenderPipelineState(linkPipeline)
                encoder.setVertexBuffer(buffers.linkVertexBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(buffers.linkBuffer, offset: 0, index: 1)
                encoder.setVertexBuffer(buffers.uniformBuffer, offset: MemoryLayout<LatticeMetalUniforms>.stride * uniformIndex, index: 2)
                encoder.setFragmentBuffer(buffers.uniformBuffer, offset: MemoryLayout<LatticeMetalUniforms>.stride * uniformIndex, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: linkCount)
            }

            if nodeCount > 0 {
                encoder.setRenderPipelineState(puckPipeline)
                encoder.setVertexBuffer(buffers.quadVertexBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(buffers.nodeBuffer, offset: 0, index: 1)
                encoder.setVertexBuffer(buffers.visibleIndexBuffer, offset: 0, index: 2)
                encoder.setVertexBuffer(buffers.uniformBuffer, offset: MemoryLayout<LatticeMetalUniforms>.stride * uniformIndex, index: 3)
                encoder.setFragmentBuffer(buffers.uniformBuffer, offset: MemoryLayout<LatticeMetalUniforms>.stride * uniformIndex, index: 0)
                encoder.setFragmentBuffer(buffers.nodeBuffer, offset: 0, index: 1)
                encoder.setFragmentBuffer(buffers.visibleIndexBuffer, offset: 0, index: 2)
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexType: .uint16,
                    indexBuffer: buffers.quadIndexBuffer,
                    indexBufferOffset: 0,
                    indirectBuffer: buffers.indirectArgsBuffer,
                    indirectBufferOffset: 0
                )
            }

            encoder.endEncoding()
        }

#if canImport(MetalFX)
        if canUseMetalFX,
           let metalFXTexture = metalFXInputTexture,
           let scaler = metalFXScaler as? any MTLFXSpatialScaler {
            scaler.inputTexture = metalFXTexture
            scaler.outputTexture = drawable.texture
            scaler.encode(commandBuffer: commandBuffer)
        }
#endif

        let debugFlags = snapshot.debugFlags
        commandBuffer.addCompletedHandler { [weak self] buffer in
            guard let self else { return }
            let visibleCount = Int(self.buffers.visibleCountBuffer.contents().bindMemory(to: UInt32.self, capacity: 1).pointee)
            self.diagnostics.lastVisibleCount = visibleCount
#if DEBUG
            let now = CACurrentMediaTime()
            if debugFlags != 0 || now - self.lastIndirectArgsLogTime >= 1.0 {
                let argsPointer = self.buffers.indirectArgsBuffer.contents().bindMemory(to: MTLDrawIndexedPrimitivesIndirectArguments.self, capacity: 1)
                let args = argsPointer.pointee
                print("[LatticeMetal] indirect instanceCount=\(args.instanceCount) visibleCount=\(visibleCount)")
                self.lastIndirectArgsLogTime = now
            }
#endif
            if pickToken != nil {
                let pointer = self.buffers.pickBuffer.contents().bindMemory(to: LatticeMetalPickResult.self, capacity: 1)
                let result = pointer.pointee
                let gpuTimeMs = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
                if let pickRequestFrame {
                    self.diagnostics.lastPickLatencyFrames = max(0, self.frameIndex - pickRequestFrame)
                }
                if buffer.gpuStartTime > 0 && buffer.gpuEndTime > buffer.gpuStartTime {
                    self.diagnostics.lastGPUTimeMs = gpuTimeMs
                }
                DispatchQueue.main.async {
                    self.onPick?(result)
                }
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        let cpuEnd = CACurrentMediaTime()
        diagnostics.lastCPUEncodeMs = (cpuEnd - cpuStart) * 1000
#if DEBUG
        if snapshot.debugFlags != 0 {
            let visibleCount = buffers.visibleCountBuffer.contents().bindMemory(to: UInt32.self, capacity: 1).pointee
            print("[LatticeMetal] cpu=\(String(format: "%.2f", diagnostics.lastCPUEncodeMs))ms gpu=\(String(format: "%.2f", diagnostics.lastGPUTimeMs))ms visible=\(visibleCount) pickLatency=\(diagnostics.lastPickLatencyFrames)f")
        }
#endif
    }

    private func rebuildMetalFXIfNeeded(view: MTKView, drawableSize: CGSize) {
#if canImport(MetalFX)
        guard #available(iOS 26.0, macCatalyst 26.0, *), useMetalFX, metalFXSupported else {
            metalFXScaler = nil
            metalFXInputTexture = nil
            metalFXOutputTexture = nil
            return
        }

        let scale: Float = 0.82
        let width = max(1, Int(Float(drawableSize.width) * scale))
        let height = max(1, Int(Float(drawableSize.height) * scale))
        let outputWidth = Int(drawableSize.width)
        let outputHeight = Int(drawableSize.height)
        let pixelFormat = view.colorPixelFormat

        if metalFXInputTexture != nil,
           metalFXOutputTexture != nil,
           metalFXScaler != nil,
           lastFXInputWidth == width,
           lastFXInputHeight == height,
           lastFXOutputWidth == outputWidth,
           lastFXOutputHeight == outputHeight,
           lastFXPixelFormat == pixelFormat {
            return
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        metalFXInputTexture = device.makeTexture(descriptor: descriptor)

        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: outputWidth,
            height: outputHeight,
            mipmapped: false
        )
        outputDescriptor.usage = [.renderTarget]
        outputDescriptor.storageMode = .private
        metalFXOutputTexture = device.makeTexture(descriptor: outputDescriptor)

        let fxDescriptor = MTLFXSpatialScalerDescriptor()
        fxDescriptor.inputWidth = width
        fxDescriptor.inputHeight = height
        fxDescriptor.outputWidth = outputWidth
        fxDescriptor.outputHeight = outputHeight
        fxDescriptor.colorTextureFormat = pixelFormat
        fxDescriptor.colorProcessingMode = .perceptual
        fxDescriptor.outputTextureFormat = pixelFormat
        metalFXScaler = fxDescriptor.makeSpatialScaler(device: device)
        if metalFXScaler == nil {
#if DEBUG
            print("[LatticeMetal] MetalFX scaler unavailable; falling back to non-MetalFX rendering.")
#endif
            metalFXSupported = false
            metalFXInputTexture = nil
            metalFXOutputTexture = nil
            lastFXInputWidth = nil
            lastFXInputHeight = nil
            lastFXOutputWidth = nil
            lastFXOutputHeight = nil
            lastFXPixelFormat = nil
            return
        }
        lastFXInputWidth = width
        lastFXInputHeight = height
        lastFXOutputWidth = outputWidth
        lastFXOutputHeight = outputHeight
        lastFXPixelFormat = pixelFormat
#else
        metalFXScaler = nil
        metalFXInputTexture = nil
        metalFXOutputTexture = nil
#endif
    }
}
