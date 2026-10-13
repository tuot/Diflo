//
//  DifloUITests.swift
//  DifloUITests
//
//  Created by Levi on 2026/8/18.
//

import AppKit
import XCTest

final class DifloUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testBlankComparisonOpensEditableTwoPaneWorkspace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()

        let blankComparison = app.buttons["空白对比"]
        XCTAssertTrue(blankComparison.waitForExistence(timeout: 3))
        blankComparison.click()

        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["新建对比"].exists)
        XCTAssertTrue(app.staticTexts["左侧未命名"].exists)
        XCTAssertTrue(app.staticTexts["右侧未命名"].exists)
        let leftEditor = app.textViews["左侧文件内容"]
        let rightEditor = app.textViews["右侧文件内容"]
        XCTAssertTrue(leftEditor.waitForExistence(timeout: 3))
        XCTAssertTrue(rightEditor.waitForExistence(timeout: 3))

        leftEditor.click()
        leftEditor.typeText("left")
        rightEditor.click()
        rightEditor.typeText("right")

        XCTAssertEqual(leftEditor.value as? String, "left")
        XCTAssertEqual(rightEditor.value as? String, "right")
        app.activate()
        XCTAssertGreaterThan(
            darkPixelCount(in: leftEditor.screenshot()),
            100,
            "左侧文本值已更新，但字形没有绘制出来"
        )
        XCTAssertGreaterThan(
            darkPixelCount(in: rightEditor.screenshot()),
            100,
            "右侧文本值已更新，但字形没有绘制出来"
        )
        XCTAssertGreaterThan(
            darkPixelRatio(in: app.buttons["返回"].screenshot()),
            0.01,
            "返回按钮虽然存在于控件树中，但被白色编辑器遮住了"
        )
    }

    private func darkPixelRatio(in screenshot: XCUIScreenshot) -> Double {
        guard let bitmap = NSBitmapImageRep(data: screenshot.pngRepresentation) else { return 0 }
        var darkPixels = 0
        let pixelCount = bitmap.pixelsWide * bitmap.pixelsHigh
        guard pixelCount > 0 else { return 0 }

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                if color.alphaComponent > 0.5, luminance < 0.75 {
                    darkPixels += 1
                }
            }
        }
        return Double(darkPixels) / Double(pixelCount)
    }

    private func darkPixelCount(in screenshot: XCUIScreenshot) -> Int {
        guard let bitmap = NSBitmapImageRep(data: screenshot.pngRepresentation) else { return 0 }
        var darkPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                if color.alphaComponent > 0.5, luminance < 0.75 {
                    darkPixels += 1
                }
            }
        }
        return darkPixels
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
