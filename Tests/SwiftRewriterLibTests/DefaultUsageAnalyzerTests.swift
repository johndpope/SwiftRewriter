import XCTest
import SwiftRewriterLib
import SwiftAST

class DefaultUsageAnalyzerTests: XCTestCase {
    func testFindMethodUsages() {
        let builder = IntentionCollectionBuilder()
        let body: CompoundStatement = [
            // B().b()
            .expression(
                .postfix(
                    .postfix(
                        .postfix(
                            .identifier("B"),
                            .functionCall(arguments: [])
                        ),
                        .member("b")
                    ),
                    .functionCall(arguments: [])
                )
            )
        ]
        
        builder
            .createFile(named: "A.m") { file in
                file
                    .createClass(withName: "A") { builder in
                        builder.createVoidMethod(named: "f1") {
                            return body
                        }
                    }
                    .createClass(withName: "B") { builder in
                        builder
                            .createConstructor()
                            .createVoidMethod(named: "b")
                    }
            }
        let intentions = builder.build(typeChecked: true)
        let sut = DefaultUsageAnalyzer(intentions: intentions)
        let method = intentions.fileIntentions()[0].typeIntentions[1].methods[0]
        
        let usages = sut.findUsagesOf(method: method)
        
        XCTAssertEqual(usages[0].expression,
                        .postfix(
                            .postfix(
                                .identifier("B"),
                                .functionCall(arguments: [])
                            ),
                            .member("b")
                        ))
        
        XCTAssertEqual(usages.count, 1)
    }
    
    func testFindMethodUsagesWithRecursiveCall() {
        let builder = IntentionCollectionBuilder()
        
        let body: CompoundStatement = [
            // B().b().b()
            .expression(
                .postfix(
                    .postfix(
                        .postfix(
                            .postfix(
                                .postfix(
                                    .identifier("B"),
                                    .functionCall(arguments: [])
                                ),
                                .member("b")
                            ),
                            .functionCall(arguments: [])
                        ),
                        .member("b")
                    ),
                    .functionCall(arguments: [])
                )
            )
        ]
        
        builder
            .createFile(named: "A.m") { file in
                file
                    .createClass(withName: "A") { builder in
                        builder.createVoidMethod(named: "f1") {
                            return body
                        }
                    }
                    .createClass(withName: "B") { builder in
                        builder
                            .createConstructor()
                            .createMethod(withSignature:
                                FunctionSignature(name: "b",
                                                  parameters: [],
                                                  returnType: .typeName("B")
                                )
                        )
                }
        }
        let intentions = builder.build(typeChecked: true)
        let sut = DefaultUsageAnalyzer(intentions: intentions)
        let method = intentions.fileIntentions()[0].typeIntentions[1].methods[0]
        
        let usages = sut.findUsagesOf(method: method)
        
        XCTAssertEqual(usages.count, 2)
    }
    
    func testFindPropertyUsages() {
        let builder = IntentionCollectionBuilder()
        
        let body: CompoundStatement = [
            // B().b()
            .expression(
                .postfix(
                    .postfix(
                        .identifier("B"),
                        .functionCall(arguments: [])
                    ),
                    .member("b")
                )
            )
        ]
        
        builder
            .createFile(named: "A.m") { file in
                file
                    .createClass(withName: "A") { builder in
                        builder.createVoidMethod(named: "f1") {
                            return body
                        }
                    }
                    .createClass(withName: "B") { builder in
                        builder
                            .createConstructor()
                            .createProperty(named: "b", type: .int)
                }
        }
        let intentions = builder.build(typeChecked: true)
        let sut = DefaultUsageAnalyzer(intentions: intentions)
        let property = intentions.fileIntentions()[0].typeIntentions[1].properties[0]
        
        let usages = sut.findUsagesOf(property: property)
        
        XCTAssertEqual(usages.count, 1)
    }
    
    func testFindEnumMemberUsage() {
        let builder = IntentionCollectionBuilder()
        
        let body: CompoundStatement = [
            // B.B_a
            .expression(
                .postfix(
                    .identifier("B"),
                    .member("B_a")
                )
            )
        ]
        
        builder
            .createFile(named: "A.m") { file in
                file
                    .createClass(withName: "A") { builder in
                        builder.createVoidMethod(named: "f1") {
                            return body
                        }
                    }
                    .createEnum(withName: "B", rawValue: .int) { builder in
                        builder.createCase(name: "B_a")
                }
            }
        
        let intentions = builder.build(typeChecked: true)
        let sut = DefaultUsageAnalyzer(intentions: intentions)
        let property = intentions.fileIntentions()[0].enumIntentions[0].cases[0]
        
        let usages = sut.findUsagesOf(property: property)
        
        XCTAssertEqual(usages.count, 1)
    }
}