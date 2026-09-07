import XCTest
@testable import OmniMac

/// Mover los iconos del notch arrastrándolos.
final class TabReorderTests: XCTestCase {
    private let all: [NotchTab] = [.media, .tray, .calendar, .sound, .timer]
    private var todas: Set<NotchTab> { Set(all) }

    func testMoveOneToTheRight() {
        let result = TabReorder.move(.media, by: 1, in: all, visible: todas)
        XCTAssertEqual(result, [.tray, .media, .calendar, .sound, .timer])
    }

    func testMoveTwoToTheLeft() {
        let result = TabReorder.move(.sound, by: -2, in: all, visible: todas)
        XCTAssertEqual(result, [.media, .sound, .tray, .calendar, .timer])
    }

    func testItStopsAtTheEdges() {
        XCTAssertEqual(TabReorder.move(.media, by: -3, in: all, visible: todas), all)
        XCTAssertEqual(TabReorder.move(.timer, by: 5, in: all, visible: todas),
                       [.media, .tray, .calendar, .sound, .timer])
        XCTAssertEqual(TabReorder.move(.media, by: 99, in: all, visible: todas),
                       [.tray, .calendar, .sound, .timer, .media])
    }

    func testNothingHappensWithoutMovement() {
        XCTAssertEqual(TabReorder.move(.calendar, by: 0, in: all, visible: todas), all)
    }

    func testHiddenTabsStayWhereTheyWere() {
        // Calendario apagado: mover Música un sitio a la derecha tiene que saltárselo
        // y dejarlo en su hueco, no colocarse detrás de él.
        let visible: Set<NotchTab> = [.media, .tray, .sound, .timer]
        let result = TabReorder.move(.media, by: 1, in: all, visible: visible)
        XCTAssertEqual(result, [.tray, .media, .calendar, .sound, .timer])
        XCTAssertEqual(result.firstIndex(of: .calendar), 2, "el calendario no se mueve de su hueco")
    }

    func testDraggingATabThatIsNotVisibleChangesNothing() {
        let visible: Set<NotchTab> = [.media, .tray]
        XCTAssertEqual(TabReorder.move(.sound, by: 1, in: all, visible: visible), all)
    }

    func testTheOrderKeepsAllTheTabs() {
        let result = TabReorder.move(.timer, by: -4, in: all, visible: todas)
        XCTAssertEqual(Set(result), Set(all))
        XCTAssertEqual(result.count, all.count)
    }
}
