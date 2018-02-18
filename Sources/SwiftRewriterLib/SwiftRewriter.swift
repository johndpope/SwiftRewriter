import GrammarModels
import ObjcParser

/// Allows re-writing Objective-C constructs into Swift equivalents.
public class SwiftRewriter {
    
    private var outputTarget: WriterOutput
    private let context: TypeContext
    private let typeMapper: TypeMapper
    private let intentionCollection: IntentionCollection
    private let sourcesProvider: InputSourcesProvider
    private var nonnullTokenRanges: [(start: Int, end: Int)] = []
    
    /// To keep token sources alive long enough.
    private var parsers: [ObjcParser] = []
    
    /// A diagnostics instance that collects all diagnostic errors during input
    /// source processing.
    public let diagnostics: Diagnostics
    
    /// An expression pass is executed for every method expression to allow custom
    /// transformations to be applied to resulting code.
    public var expressionPasses: [ExpressionPass] = []
    
    public init(input: InputSourcesProvider, output: WriterOutput) {
        self.diagnostics = Diagnostics()
        self.sourcesProvider = input
        self.outputTarget = output
        self.context = TypeContext()
        self.typeMapper = TypeMapper(context: context)
        self.intentionCollection = IntentionCollection()
    }
    
    public func rewrite() throws {
        parsers.removeAll()
        
        try loadInputSources()
        performIntentionPasses()
        outputDefinitions()
    }
    
    private func loadInputSources() throws {
        // Load input sources
        let sources = sourcesProvider.sources()
        
        for src in sources {
            try loadObjcSource(from: src)
        }
    }
    
    private func loadObjcSource(from source: InputSource) throws {
        // Generate intention for this source
        let fileIntent = FileGenerationIntention(filePath: source.sourceName())
        intentionCollection.addIntention(fileIntent)
        context.pushContext(fileIntent)
        context.pushContext(AssumeNonnullContext(isNonnullOn: false))
        defer {
            context.popContext()
        }
        
        let src = try source.loadSource()
        
        let parser = ObjcParser(source: src)
        parsers.append(parser)
        parser.diagnostics = diagnostics
        
        try parser.parse()
        
        nonnullTokenRanges = parser.nonnullMacroRegionsTokenRange
        
        let node = parser.rootNode
        let visitor = AnonymousASTVisitor()
        let traverser = ASTTraverser(node: node, visitor: visitor)
        
        visitor.onEnterClosure = { node in
            self.context.findContext(ofType: AssumeNonnullContext.self)?.isNonnullOn =
                self.isNodeInNonnullContext(node)
            
            switch node {
            case let n as ObjcClassInterface:
                self.enterObjcClassInterfaceNode(n)
            case let n as ObjcClassCategory:
                self.enterObjcClassCategoryNode(n)
            case let n as ObjcClassImplementation:
                self.enterObjcClassImplementationNode(n)
            case let n as ObjcClassCategoryImplementation:
                self.enterObjcClassCategoryImplementationNode(n)
            case let n as ProtocolDeclaration:
                self.enterProtocolDeclarationNode(n)
            case let n as IVarsList:
                self.enterObjcClassIVarsListNode(n)
            default:
                return
            }
        }
        
        visitor.visitClosure = { node in
            switch node {
            case let n as TypedefNode:
                self.visitTypedefNode(n)
                
            case let n as KeywordNode:
                self.visitKeywordNode(n)
            
            case let n as MethodDefinition:
                self.visitObjcClassMethodNode(n)
            
            case let n as PropertyDefinition:
                self.visitPropertyDefinitionNode(n)
                
            case let n as ProtocolReferenceList:
                self.visitObjcClassProtocolReferenceListNode(n)
                
            case let n as SuperclassName:
                self.visitObjcClassSuperclassName(n)
                
            case let n as IVarDeclaration:
                self.visitObjcClassIVarDeclarationNode(n)
                
            case let n as VariableDeclaration:
                self.visitVariableDeclarationNode(n)
                
            case let n as Identifier
                where n.name == "NS_ASSUME_NONNULL_BEGIN":
                self.context.findContext(ofType: AssumeNonnullContext.self)?.isNonnullOn = true
                
            case let n as Identifier
                where n.name == "NS_ASSUME_NONNULL_END":
                self.context.findContext(ofType: AssumeNonnullContext.self)?.isNonnullOn = false
            default:
                return
            }
        }
        
        visitor.onExitClosure = { node in
            switch node {
            case let n as ObjcClassInterface:
                self.exitObjcClassInterfaceNode(n)
            case let n as ObjcClassCategory:
                self.exitObjcClassCategoryNode(n)
            case let n as ObjcClassImplementation:
                self.exitObjcClassImplementationNode(n)
            case let n as ObjcClassCategoryImplementation:
                self.exitObjcClassCategoryImplementationNode(n)
            case let n as ProtocolDeclaration:
                self.exitProtocolDeclarationNode(n)
            case let n as IVarsList:
                self.exitObjcClassIVarsListNode(n)
            default:
                return
            }
        }
        
        traverser.traverse()
    }
    
    private func performIntentionPasses() {
        for pass in IntentionPasses.passes {
            pass.apply(on: intentionCollection)
        }
    }
    
    private func outputDefinitions() {
        let writer = SwiftWriter(intentions: intentionCollection,
                                 diagnostics: diagnostics,
                                 output: outputTarget)
        
        writer.expressionPasses = expressionPasses
        writer.execute()
    }
    
    private func isNodeInNonnullContext(_ node: ASTNode) -> Bool {
        guard let ruleContext = node.sourceRuleContext else {
            return false
        }
        guard let startToken = ruleContext.getStart(), let stopToken = ruleContext.getStop() else {
            return false
        }
        
        for n in nonnullTokenRanges {
            if n.start <= startToken.getTokenIndex() && n.end >= stopToken.getTokenIndex() {
                return true
            }
        }
        
        return false
    }
    
    private func visitTypedefNode(_ node: TypedefNode) {
        guard let ctx = context.findContext(ofType: FileGenerationIntention.self) else {
            return
        }
        guard let type = node.type else {
            return
        }
        guard let name = node.identifier?.name else {
            return
        }
        
        let intent = TypealiasIntention(fromType: type.type, named: name)
        intent.inNonnullContext = isNodeInNonnullContext(node)
        
        ctx.addTypealias(intent)
    }
    
    private func visitKeywordNode(_ node: KeywordNode) {
        // ivar list accessibility specification
        if let ctx = context.findContext(ofType: IVarListContext.self) {
            switch node.keyword {
            case .atPrivate:
                ctx.accessLevel = .private
            case .atPublic:
                ctx.accessLevel = .public
            case .atPackage:
                ctx.accessLevel = .internal
            case .atProtected:
                ctx.accessLevel = .internal
            default:
                break
            }
        }
    }
    
    private func visitVariableDeclarationNode(_ node: VariableDeclaration) {
        guard let ctx = context.findContext(ofType: FileGenerationIntention.self) else {
            return
        }
        
        guard let name = node.identifier, let type = node.type else {
            return
        }
        
        let typeContext =
            TypeMapper.TypeMappingContext(inNonnull: isNodeInNonnullContext(node))
        
        let swiftType = typeMapper.swiftType(forObjcType: type.type, context: typeContext)
        let ownership = evaluateOwnershipPrefix(inType: type.type)
        let isConstant = SwiftWriter._isConstant(fromType: type.type)
        
        let storage =
            ValueStorage(type: swiftType, ownership: ownership, isConstant: isConstant)
        
        let intent =
            GlobalVariableGenerationIntention(name: name.name, storage: storage,
                                              source: node)
        
        intent.inNonnullContext = isNodeInNonnullContext(node)
        
        if let initialExpression = node.initialExpression,
            let expression = initialExpression.expression?.expression?.expression {
            let rewriter = SwiftStmtRewriter(expressionPasses: expressionPasses)
            let expression = rewriter.parseExpression(expression: expression)
            
            intent.initialValueExpr =
                GlobalVariableInitialValueIntention(expression: expression,
                                                    source: initialExpression)
        }
        
        ctx.addGlobalVariable(intent)
    }
    
    // MARK: - ObjcClassInterface
    private func enterObjcClassInterfaceNode(_ node: ObjcClassInterface) {
        guard let name = node.identifier.name else {
            return
        }
        
        let intent =
            ClassGenerationIntention(typeName: name, source: node)
        
        intentionCollection.addIntention(intent)
        
        context
            .findContext(ofType: FileGenerationIntention.self)?
            .addType(intent)
        
        context.pushContext(intent)
    }
    
    private func exitObjcClassInterfaceNode(_ node: ObjcClassInterface) {
        if node.identifier.name != nil {
            context.popContext() // ClassGenerationIntention
        }
    }
    
    // MARK: - ObjcClassCategory
    private func enterObjcClassCategoryNode(_ node: ObjcClassCategory) {
        guard let name = node.identifier?.name else {
            return
        }
        
        let intent =
            ClassExtensionGenerationIntention(typeName: name, source: node)
        intent.extensionName = node.categoryName?.name
        
        intentionCollection.addIntention(intent)
        
        context
            .findContext(ofType: FileGenerationIntention.self)?
            .addType(intent)
        
        context.pushContext(intent)
    }
    
    private func exitObjcClassCategoryNode(_ node: ObjcClassCategory) {
        if node.identifier?.name != nil {
            context.popContext() // ClassExtensionGenerationIntention
        }
    }
    
    // MARK: - ObjcClassImplementation
    private func enterObjcClassImplementationNode(_ node: ObjcClassImplementation) {
        guard let name = node.identifier?.name else {
            return
        }
        
        let intent =
            ClassGenerationIntention(typeName: name, source: node)
        
        intentionCollection.addIntention(intent)
        
        context
            .findContext(ofType: FileGenerationIntention.self)?
            .addType(intent)
        
        context.pushContext(intent)
    }
    
    private func exitObjcClassImplementationNode(_ node: ObjcClassImplementation) {
        context.popContext() // ClassGenerationIntention
    }
    
    // MARK: - ObjcClassCategoryImplementation
    private func enterObjcClassCategoryImplementationNode(_ node: ObjcClassCategoryImplementation) {
        guard let name = node.identifier?.name else {
            return
        }
        
        let intent =
            ClassExtensionGenerationIntention(typeName: name, source: node)
        intent.extensionName = node.categoryName?.name
        
        intentionCollection.addIntention(intent)
        
        context
            .findContext(ofType: FileGenerationIntention.self)?
            .addType(intent)
        
        context.pushContext(intent)
    }
    
    private func exitObjcClassCategoryImplementationNode(_ node: ObjcClassCategoryImplementation) {
        context.popContext() // ClassExtensionGenerationIntention
    }
    
    // MARK: - ProtocolDeclaration
    private func enterProtocolDeclarationNode(_ node: ProtocolDeclaration) {
        guard let name = node.identifier?.name else {
            return
        }
        
        let intent =
            ProtocolGenerationIntention(typeName: name, source: node)
        
        intentionCollection.addIntention(intent)
        
        context
            .findContext(ofType: FileGenerationIntention.self)?
            .addProtocol(intent)
        
        context.pushContext(intent)
    }
    
    private func exitProtocolDeclarationNode(_ node: ProtocolDeclaration) {
        if node.identifier?.name != nil {
            context.popContext() // ProtocolGenerationIntention
        }
    }
    private func visitPropertyDefinitionNode(_ node: PropertyDefinition) {
        guard let ctx = context.findContext(ofType: TypeGenerationIntention.self) else {
            return
        }
        
        var swiftType: SwiftType = .anyObject
        var ownership: Ownership = .strong
        if let type = node.type?.type {
            let context = TypeMapper
                .TypeMappingContext(modifiers: node.attributesList, inNonnull: isNodeInNonnullContext(node))
            
            swiftType = typeMapper.swiftType(forObjcType: type, context: context)
            ownership = evaluateOwnershipPrefix(inType: type, property: node)
        }
        
        let attributes =
            node.attributesList?
                .attributes.map { attr -> PropertyAttribute in
                    switch attr.attribute {
                    case .getter(let getter):
                        return PropertyAttribute.getterName(getter)
                    case .setter(let setter):
                        return PropertyAttribute.setterName(setter)
                    case .keyword(let keyword):
                        return PropertyAttribute.attribute(keyword)
                    }
                } ?? []
        
        let storage =
            ValueStorage(type: swiftType, ownership: ownership, isConstant: false)
        
        // Protocol property
        if context.findContext(ofType: ProtocolGenerationIntention.self) != nil {
            let prop =
                ProtocolPropertyGenerationIntention(name: node.identifier?.name ?? "",
                                                    storage: storage, attributes: attributes,
                                                    source: node)
            
            prop.isOptional = node.isOptionalProperty
            
            prop.inNonnullContext = isNodeInNonnullContext(node)
            
            ctx.addProperty(prop)
        } else {
            let prop =
                PropertyGenerationIntention(name: node.identifier?.name ?? "",
                                            storage: storage, attributes: attributes,
                                            source: node)
            
            prop.inNonnullContext = isNodeInNonnullContext(node)
            
            ctx.addProperty(prop)
        }
    }
    
    private func visitObjcClassMethodNode(_ node: MethodDefinition) {
        guard let ctx = context.findContext(ofType: TypeGenerationIntention.self) else {
            return
        }
        
        let signGen = SwiftMethodSignatureGen(context: context, typeMapper: typeMapper)
        let sign = signGen.generateDefinitionSignature(from: node)
        
        let method: MethodGenerationIntention
        
        if context.findContext(ofType: ProtocolGenerationIntention.self) != nil {
            let protMethod = ProtocolMethodGenerationIntention(signature: sign, source: node)
            protMethod.isOptional = node.isOptionalMethod
            
            method = protMethod
        } else {
            method = MethodGenerationIntention(signature: sign, source: node)
        }
        
        method.inNonnullContext = isNodeInNonnullContext(node)
        
        if let body = node.body, let statements = body.statements {
            let rewriter = SwiftStmtRewriter(expressionPasses: expressionPasses)
            let compound = rewriter.parseStatements(compoundStatement: statements)
            
            let methodBodyIntention = MethodBodyIntention(body: compound, source: body)
            method.body = methodBodyIntention
        }
        
        ctx.addMethod(method)
    }
    
    private func visitObjcClassSuperclassName(_ node: SuperclassName) {
        guard let ctx = context.findContext(ofType: ClassGenerationIntention.self) else {
            return
        }
        
        ctx.superclassName = node.name
    }
    
    private func visitObjcClassProtocolReferenceListNode(_ node: ProtocolReferenceList) {
        guard let ctx = context.findContext(ofType: TypeGenerationIntention.self) else {
            return
        }
        
        for protNode in node.protocols {
            let intent = ProtocolInheritanceIntention(protocolName: protNode.name, source: protNode)
            
            ctx.addProtocol(intent)
        }
    }
    
    // MARK: - IVar Section
    private func enterObjcClassIVarsListNode(_ node: IVarsList) {
        let ctx = IVarListContext(accessLevel: .private)
        context.pushContext(ctx)
    }
    
    private func visitObjcClassIVarDeclarationNode(_ node: IVarDeclaration) {
        guard let classCtx = context.findContext(ofType: BaseClassIntention.self) else {
            return
        }
        let ivarCtx = context.findContext(ofType: IVarListContext.self)
        
        let access = ivarCtx?.accessLevel ?? .private
        
        var swiftType: SwiftType = .anyObject
        var ownership = Ownership.strong
        var isConstant = false
        if let type = node.type?.type {
            swiftType = typeMapper.swiftType(forObjcType: type,
                                             context: .init(inNonnull: isNodeInNonnullContext(node)))
            ownership = evaluateOwnershipPrefix(inType: type)
            isConstant = SwiftWriter._isConstant(fromType: type)
        }
        
        let storage = ValueStorage(type: swiftType, ownership: ownership, isConstant: isConstant)
        let ivar =
            InstanceVariableGenerationIntention(name: node.identifier?.name ?? "",
                                                storage: storage, accessLevel: access,
                                                source: node)
        
        ivar.inNonnullContext = isNodeInNonnullContext(node)
        
        classCtx.addInstanceVariable(ivar)
    }
    
    private func exitObjcClassIVarsListNode(_ node: IVarsList) {
        context.popContext() // InstanceVarContext
    }
    // MARK: -
    
    private class IVarListContext: Context {
        var accessLevel: AccessLevel
        
        init(accessLevel: AccessLevel = .private) {
            self.accessLevel = accessLevel
        }
    }
}
