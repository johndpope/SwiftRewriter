import XCTest
import SwiftRewriterLib
import SwiftAST

class SwiftRewriter_IntentionPassHistoryTests: XCTestCase {
    func testPrintIntentionHistory() throws {
        assertObjcParse(
            objc: """
            @implementation MyClass
            - (void)setValue:(BOOL)value {
                
            }
            - (BOOL)value {
                return NO;
            }
            - (NSString*)aMethod {
            }
            @end
            
            @interface MyClass
            @property BOOL value;

            - (nonnull NSString*)aMethod;
            @end
            """,
            swift: """
            // [Creation]  line 1 column 1
            // [Creation]  line 12 column 1
            // [PropertyMergeIntentionPass:1] Removed method MyClass.value() -> Bool since deduced it is a getter for property MyClass.value: Bool
            // [PropertyMergeIntentionPass:1] Removed method MyClass.setValue(_ value: Bool) since deduced it is a setter for property MyClass.value: Bool
            class MyClass {
                // [Creation]  line 13 column 1
                // [PropertyMergeIntentionPass:1] Merged MyClass.value() -> Bool and MyClass.setValue(_ value: Bool) into property MyClass.value: Bool
                var value: Bool {
                    get {
                        return false
                    }
                    set(value) {
                    }
                }
                
                // [Creation]  line 8 column 3
                // [TypeMerge] Updated nullability signature from () -> String! to: () -> String
                func aMethod() -> String {
                }
            }
            """,
            options: ASTWriterOptions(printIntentionHistory: true))
    }
}
