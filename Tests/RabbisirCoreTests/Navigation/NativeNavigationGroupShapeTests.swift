import SwiftUI
import Testing

@testable import RabbisirCore

@Suite("Native navigation group shape")
struct NativeNavigationGroupShapeTests {
  @Test("The group is flush on the leading edge and rounded only on the trailing edge")
  func trailingCornersOnly() {
    let rect = CGRect(x: 0, y: 0, width: 240, height: 180)
    let path = NativeNavigationGroupShape(trailingRadius: 12).path(in: rect)

    #expect(path.contains(CGPoint(x: rect.minX + 0.5, y: rect.minY + 0.5)))
    #expect(path.contains(CGPoint(x: rect.minX + 0.5, y: rect.maxY - 0.5)))
    #expect(!path.contains(CGPoint(x: rect.maxX - 0.5, y: rect.minY + 0.5)))
    #expect(!path.contains(CGPoint(x: rect.maxX - 0.5, y: rect.maxY - 0.5)))
    #expect(path.contains(CGPoint(x: rect.maxX - 12, y: rect.minY + 1)))
    #expect(path.contains(CGPoint(x: rect.maxX - 1, y: rect.minY + 12)))
  }

  @Test("The project glass extends without absorbing the action button surfaces")
  func projectGlassExcludesActionButtonSurfaces() {
    let rect = CGRect(x: 0, y: 0, width: 361, height: 34)
    let path = NativeNavigationGroupShape(
      trailingRadius: 12,
      projectRowHeight: 34,
      projectExtensionWidth: 18,
      baseWidth: 240
    ).path(in: rect)

    #expect(path.contains(CGPoint(x: 250, y: rect.midY)))
    #expect(!path.contains(CGPoint(x: 273, y: rect.midY)))
    #expect(!path.contains(CGPoint(x: 351, y: rect.midY)))
    #expect(!path.contains(CGPoint(x: 360, y: rect.midY)))
    #expect(!path.contains(CGPoint(x: 362, y: rect.midY)))
  }

  @Test("Reserved interaction width does not become part of the project surface")
  func reservedInteractionWidthKeepsStableBaseWidth() {
    let rect = CGRect(x: 0, y: 0, width: 220, height: 34)
    let path = NativeNavigationGroupShape(
      trailingRadius: 12,
      projectRowHeight: 34,
      projectExtensionWidth: 18,
      reservedTrailingWidth: 100
    ).path(in: rect)

    #expect(path.boundingRect.minX == 0)
    #expect(path.boundingRect.maxX == 138)
  }
}
