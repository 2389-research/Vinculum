import XCTest
import Foundation
@testable import VinculumLayout

/// MathVariants parsing (variants + GlyphAssembly) against
/// the committed LM Math fixture (fontTools ground truth in comments), and
/// the pure assembly solver.
final class MathAssemblyTests: XCTestCase {

    private static let fixture = TestFixtures.mathTable("latinmodern-math")

    // MARK: - MathVariants parsing

    func testMinConnectorOverlapAndParenLadder() throws {
        let v = try XCTUnwrap(MathTableParser.variants(from: Self.fixture, unitsPerEm: 1000))
        XCTAssertEqual(v.minConnectorOverlap, 0.020)
        // fontTools: parenleft gid 9 → 8 variants, first three advances
        // 997 / 1095 / 1195, variant gids 9, 2367, 2389.
        let paren = try XCTUnwrap(v.vertical[9])
        XCTAssertEqual(paren.variants.count, 8)
        XCTAssertEqual(paren.variants[1].glyphID, 2367)
        XCTAssertEqual(paren.variants[1].advance, 1.095)
        XCTAssertEqual(paren.variants[2].advance, 1.195)
    }

    func testAngleBracketLadderIsCorrectlyMapped() throws {
        // ⟨ (uni27E8, gid 2579) was excluded from the old verified-set gate
        // as "mis-mapped"; the coverage-correct parser reads its true ladder:
        // 8 variants, second = uni27E8.v1 gid 2583 advance 1101.
        let v = try XCTUnwrap(MathTableParser.variants(from: Self.fixture, unitsPerEm: 1000))
        let angle = try XCTUnwrap(v.vertical[2579])
        XCTAssertEqual(angle.variants.count, 8)
        XCTAssertEqual(angle.variants[1].glyphID, 2583)
        XCTAssertEqual(angle.variants[1].advance, 1.101)
        XCTAssertNil(angle.assembly, "angle brackets cannot extend")
    }

    func testParenAssemblyParts() throws {
        // fontTools: ( assembles bottom-to-top as uni239D (gid 2503, full
        // 1495, end 249) · uni239C extender (gid 2504, 498/498/498) ·
        // uni239B (gid 2505, start 249).
        let v = try XCTUnwrap(MathTableParser.variants(from: Self.fixture, unitsPerEm: 1000))
        let asm = try XCTUnwrap(v.vertical[9]?.assembly)
        XCTAssertEqual(asm.parts.count, 3)
        XCTAssertEqual(asm.parts[0].glyphID, 2503)
        XCTAssertEqual(asm.parts[0].endConnector, 0.249)
        XCTAssertTrue(asm.parts[1].isExtender)
        XCTAssertEqual(asm.parts[1].fullAdvance, 0.498)
        XCTAssertEqual(asm.parts[2].glyphID, 2505)
    }

    func testBraceAssemblyHasFivePartsTwoExtenderSlots() throws {
        // { : uni23A9 · ex · uni23A8 (the middle hook) · ex · uni23A7.
        let v = try XCTUnwrap(MathTableParser.variants(from: Self.fixture, unitsPerEm: 1000))
        let asm = try XCTUnwrap(v.vertical[92]?.assembly)
        XCTAssertEqual(asm.parts.count, 5)
        XCTAssertEqual(asm.parts.filter(\.isExtender).count, 2)
        XCTAssertEqual(asm.parts[2].glyphID, 2519, "middle hook uni23A8")
    }

    func testDegenerateExtenderInvalidatesAssembly() {
        // An extender with fullAdvance ≤ 0 would loop forever; such an
        // assembly is dropped at parse.
        let parts = [
            MathGlyphAssembly.Part(glyphID: 1, startConnector: 0, endConnector: 0.1, fullAdvance: 1, isExtender: false),
            MathGlyphAssembly.Part(glyphID: 2, startConnector: 0.1, endConnector: 0.1, fullAdvance: 0, isExtender: true),
        ]
        let asm = MathGlyphAssembly(italicsCorrection: 0, parts: parts)
        XCTAssertNil(MathAssemblySolver.solve(asm, minOverlap: 0.02, target: 5))
    }

    // MARK: - The pure solver

    private let parenAssembly = MathGlyphAssembly(italicsCorrection: 0, parts: [
        .init(glyphID: 2503, startConnector: 0, endConnector: 0.249, fullAdvance: 1.495, isExtender: false),
        .init(glyphID: 2504, startConnector: 0.498, endConnector: 0.498, fullAdvance: 0.498, isExtender: true),
        .init(glyphID: 2505, startConnector: 0.249, endConnector: 0, fullAdvance: 1.495, isExtender: false),
    ])

    func testSolverUsesNoExtendersWhenCapsSuffice() throws {
        // Target 2.6 em: bottom+top at max overlap reach 2·1.495 − 0.249 =
        // 2.741 ≥ 2.6 — no extender needed, height 2.741.
        let s = try XCTUnwrap(MathAssemblySolver.solve(parenAssembly, minOverlap: 0.020, target: 2.6))
        XCTAssertEqual(s.placements.map(\.glyphID), [2503, 2505])
        XCTAssertEqual(s.total, 2.741, accuracy: 0.0001)
        XCTAssertEqual(s.placements[1].offset, 1.495 - 0.249, accuracy: 0.0001)
    }

    func testSolverAddsExtenderAndDistributesSlack() throws {
        // Target 3.0 em: one extender; min 2.99, max 3.448 — the 0.01
        // shortfall spreads across both joints, total exactly 3.0.
        let s = try XCTUnwrap(MathAssemblySolver.solve(parenAssembly, minOverlap: 0.020, target: 3.0))
        XCTAssertEqual(s.placements.map(\.glyphID), [2503, 2504, 2505])
        XCTAssertEqual(s.total, 3.0, accuracy: 0.0001)
        // Joints shrink equally from max overlap 0.249.
        let joint1 = s.placements[1].offset - (1.495 - 0.249)
        let joint2 = (s.placements[2].offset - s.placements[1].offset) - (0.498 - 0.249)
        XCTAssertEqual(joint1, joint2, accuracy: 0.0001)
    }

    func testSolverGrowsExtendersForHugeTargets() throws {
        // Target 12 em needs many extender repeats; the column must reach it.
        let s = try XCTUnwrap(MathAssemblySolver.solve(parenAssembly, minOverlap: 0.020, target: 12))
        XCTAssertGreaterThanOrEqual(s.total + 0.0001, 12)
        XCTAssertGreaterThan(s.placements.count, 10)
        // Offsets strictly increase (no part overlaps entirely).
        for i in 1..<s.placements.count {
            XCTAssertGreaterThan(s.placements[i].offset, s.placements[i - 1].offset)
        }
    }
}
