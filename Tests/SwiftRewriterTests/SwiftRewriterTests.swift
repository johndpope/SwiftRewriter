import XCTest
import SwiftRewriter
import ObjcParser
import GrammarModels

class SwiftRewriterTests: XCTestCase {
    
    func testRewriteEmptyClass() throws {
        try assertObjcTypeParse(
            objc: """
            @interface MyClass
            @end
            """,
            swift: """
            class MyClass {
            }
            """)
    }
    
    func testRewriteClassProperties() throws {
        try assertObjcTypeParse(
            objc: """
            @interface MyClass
            @property BOOL someField;
            @property NSInteger someOtherField;
            @property (nonnull) NSString* aRatherStringlyField;
            @property (nullable) NSString* specifiedNull;
            @property NSString *_Nonnull nonNullWithQualifier;
            @property NSString* nonSpecifiedNull;
            @property id idType;
            @property (weak) id<MyDelegate, MyDataSource> delegate;
            @property (assign, nonnull) MyClass* assignProp;
            @end
            """,
            swift: """
            class MyClass {
                var someField: Bool
                var someOtherField: Int
                var aRatherStringlyField: String
                var specifiedNull: String?
                var nonNullWithQualifier: String
                var nonSpecifiedNull: String!
                var idType: AnyObject!
                weak var delegate: AnyObject<MyDelegate, MyDataSource>?
                unowned(unsafe) var assignProp: MyClass
            }
            """)
    }
    
    func testRewriteNSArray() throws {
        try assertObjcTypeParse(
            objc: """
            @interface MyClass
            @property (nonnull) NSArray* nontypedArray;
            @property (nullable) NSArray* nontypedArrayNull;
            @property NSArray<NSString*>* stringArray;
            @property (nonnull) NSArray<SomeType*>* clsArray;
            @property (nullable) NSArray<SomeType*>* clsArrayNull;
            @end
            """,
            swift: """
            class MyClass {
                var nontypedArray: NSArray
                var nontypedArrayNull: NSArray?
                var stringArray: [String]!
                var clsArray: [SomeType]
                var clsArrayNull: [SomeType]?
            }
            """)
    }
    
    func testRewriteEmptyMethod() throws {
        try assertObjcTypeParse(
            objc: """
            @interface MyClass
            - (void)myMethod;
            @end
            """,
            swift: """
            class MyClass {
                func myMethod() {
                }
            }
            """)
    }
    
    func testRewriteMethodSignatures() throws {
        try assertObjcTypeParse(
            objc: """
            @interface MyClass
            - (void)myMethod;
            - (NSInteger)myOtherMethod:(NSInteger)abc aString:(nonnull NSString*)str;
            - (NSInteger)myAnonParamMethod:(NSInteger)abc :(nonnull NSString*)str;
            - (nullable NSArray*)someNullArray;
            - (void):a;
            @end
            """,
            swift: """
            class MyClass {
                func myMethod() {
                }
                func myOtherMethod(abc: Int, aString str: String) -> Int {
                }
                func myAnonParamMethod(abc: Int, _ str: String) -> Int {
                }
                func someNullArray() -> NSArray? {
                }
                func __(a: AnyObject!) {
                }
            }
            """)
    }
    
    func testRewriteInitMethods() throws {
        try assertObjcTypeParse(
            objc: """
            @interface MyClass
            - (instancetype)init;
            - (instancetype)initWithNumber:(nonnull NSNumber*)number;
            @end
            """,
            swift: """
            class MyClass {
                init() {
                }
                init(with number: NSNumber) {
                }
            }
            """)
    }
    
    private func assertObjcTypeParse(objc: String, swift expectedSwift: String, file: String = #file, line: Int = #line) throws {
        let output = TestWriterOutput()
        let input = TestSingleInputProvider(code: objc)
        
        let sut = SwiftRewriter(input: input, output: output)
        
        do {
            try sut.rewrite()
            
            if output.buffer != expectedSwift {
                recordFailure(withDescription: "Failed: Expected to translate Objective-C \(objc) as \(expectedSwift), but translate as \(output.buffer)", inFile: file, atLine: line, expected: false)
            }
            
            if sut.diagnostics.errors.count != 0 {
                recordFailure(withDescription: "Unexpected error(s) parsing objective-c: \(sut.diagnostics.errors.description)", inFile: file, atLine: line, expected: false)
            }
        } catch {
            recordFailure(withDescription: "Unexpected error(s) parsing objective-c: \(error)", inFile: file, atLine: line, expected: false)
        }
    }
}

class TestSingleInputProvider: InputSourcesProvider, InputSource {
    var code: String
    
    init(code: String) {
        self.code = code
    }
    
    func sources() -> [InputSource] {
        return [self]
    }
    
    func sourceName() -> String {
        return "\(type(of: self))"
    }
    
    func loadSource() throws -> CodeSource {
        return StringCodeSource(source: code)
    }
}

class TestWriterOutput: WriterOutput, FileOutput {
    var buffer: String = ""
    
    func createFile(path: String) -> FileOutput {
        return self
    }
    
    func close() {
        
    }
    
    func outputTarget() -> RewriterOutputTarget {
        let target = StringRewriterOutput()
        
        target.onChangeBuffer = { value in
            self.buffer = value
        }
        
        return target
    }
}