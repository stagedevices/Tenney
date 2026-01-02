//
//  UnsafeMutableAudioBufferListPointer.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/1/26.
//


#if targetEnvironment(macCatalyst)
import AudioToolbox

/// Shim for toolchains where Apple’s `UnsafeMutableAudioBufferListPointer` overlay isn’t available on macOS.
/// This makes existing render-code compile unchanged.
public struct UnsafeMutableAudioBufferListPointer: RandomAccessCollection, MutableCollection {
    public typealias Index = Int
    public typealias Element = AudioBuffer

    private let abl: UnsafeMutablePointer<AudioBufferList>

    public init(_ abl: UnsafeMutablePointer<AudioBufferList>) {
        self.abl = abl
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { Int(abl.pointee.mNumberBuffers) }

    @inline(__always)
    private func base() -> UnsafeMutablePointer<AudioBuffer> {
        // `mBuffers` is the first element of the variable-length AudioBuffer array.
        UnsafeMutablePointer<AudioBuffer>(&abl.pointee.mBuffers)
    }

    public subscript(position: Int) -> AudioBuffer {
        get { base().advanced(by: position).pointee }
        set { base().advanced(by: position).pointee = newValue }
    }

    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }
}
#endif
