import SwiftAST
import SwiftRewriterLib
import Commons

public class BaseGlobalsProvider: GlobalsProvider {
    var globals: [CodeDefinition] = []
    private(set) var types: [KnownType] = []
    var typealiases: [String: SwiftType] = [:]
    var canonicalMapping: [String: String] = [:]
    
    init() {
        createDefinitions()
        createTypes()
        createTypealiases()
        createCanonicalMappings()
    }
    
    public func definitionsSource() -> DefinitionsSource {
        return ArrayDefinitionsSource(definitions: globals)
    }
    
    public func typealiasProvider() -> TypealiasProvider {
        return CollectionTypealiasProvider(aliases: typealiases)
    }
    
    public func knownTypeProvider() -> KnownTypeProvider {
        return CollectionKnownTypeProvider(knownTypes: types)
    }
    
    func createDefinitions() {
        
    }
    
    func createTypes() {
        
    }
    
    func createTypealiases() {
        
    }
    
    func createCanonicalMappings() {
        for case let compoundedType as CompoundedMappingType in types {
            addCanonicalMappings(from: compoundedType)
        }
    }
    
    func addTypealias(from source: String, to target: SwiftType) {
        typealiases[source] = target
    }
    
    func add(_ definition: CodeDefinition) {
        globals.append(definition)
    }
    
    func add(_ type: KnownType) {
        types.append(type)
    }
    
    func addCanonicalMappings(from type: CompoundedMappingType) {
        for alias in type.nonCanonicalNames {
            canonicalMapping[alias] = type.typeName
        }
    }
    
    func makeType(named name: String,
                  supertype: KnownTypeReferenceConvertible? = nil,
                  kind: KnownTypeKind = .class,
                  initializer: (KnownTypeBuilder) -> (KnownType) = { $0.build() }) {
        
        let builder = KnownTypeBuilder(typeName: name, supertype: supertype, kind: kind)
        
        let type = initializer(builder)
        
        add(type)
    }
    
    func constant(name: String, type: SwiftType) -> CodeDefinition {
        return CodeDefinition(constantNamed: name, type: type)
    }
    
    func variable(name: String, type: SwiftType) -> CodeDefinition {
        return CodeDefinition(variableNamed: name, type: type)
    }
    
    func function(name: String, paramsSignature: String, returnType: SwiftType = .void) -> CodeDefinition {
        let params = try! FunctionSignatureParser.parseParameters(from: paramsSignature)
        
        let signature =
            FunctionSignature(name: name, parameters: params,
                              returnType: returnType, isStatic: false)
        
        let definition = CodeDefinition(functionSignature: signature)
        
        return definition
    }
    
    func function(name: String, paramTypes: [SwiftType], returnType: SwiftType = .void) -> CodeDefinition {
        let paramSignatures = paramTypes.enumerated().map { (arg) -> ParameterSignature in
            let (i, type) = arg
            return ParameterSignature(label: nil, name: "p\(i)", type: type)
        }
        
        let signature =
            FunctionSignature(name: name, parameters: paramSignatures,
                              returnType: returnType, isStatic: false)
        
        let definition = CodeDefinition(functionSignature: signature)
        
        return definition
    }
}
