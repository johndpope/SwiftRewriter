import Foundation
import Utils

public protocol FunctionBodyQueueDelegate: class {
    associatedtype Context
    
    func makeContext(forFunction function: GlobalFunctionGenerationIntention) -> Context
    
    func makeContext(forInit ctor: InitGenerationIntention) -> Context
    
    func makeContext(forMethod method: MethodGenerationIntention) -> Context
    
    func makeContext(forPropertyGetter property: PropertyGenerationIntention,
                     getter: FunctionBodyIntention) -> Context
    
    func makeContext(forPropertySetter property: PropertyGenerationIntention,
                     setter: PropertyGenerationIntention.Setter) -> Context
}

/// Allows collecting function bodies across intention collections from functions,
/// methods and properties.
public class FunctionBodyQueue<Delegate: FunctionBodyQueueDelegate> {
    public typealias Context = Delegate.Context
    
    public static func fromFile(_ intentionCollection: IntentionCollection,
                                file: FileGenerationIntention,
                                delegate: Delegate) -> FunctionBodyQueue {
        
        let queue = FunctionBodyQueue(intentionCollection, delegate: delegate)
        queue.collectFromFile(file)
        
        return queue
    }
    
    public static func fromIntentionCollection(_ intentionCollection: IntentionCollection,
                                               delegate: Delegate) -> FunctionBodyQueue {
        
        let queue = FunctionBodyQueue(intentionCollection, delegate: delegate)
        queue.collect(from: intentionCollection)
        
        return queue
    }
    
    public static func fromMethod(_ intentionCollection: IntentionCollection,
                                  method: MethodGenerationIntention,
                                  delegate: Delegate) -> FunctionBodyQueue {
        
        let queue = FunctionBodyQueue(intentionCollection, delegate: delegate)
        queue.collectMethod(method)
        
        return queue
    }
    
    public static func fromProperty(_ intentionCollection: IntentionCollection,
                                    property: PropertyGenerationIntention,
                                    delegate: Delegate) -> FunctionBodyQueue {
        
        let queue = FunctionBodyQueue(intentionCollection, delegate: delegate)
        queue.collectProperty(property)
        
        return queue
    }
    
    private var intentionCollection: IntentionCollection
    private weak var delegate: Delegate?
    
    public var items: [FunctionBodyQueueItem] = []
    
    private init(_ intentionCollection: IntentionCollection, delegate: Delegate) {
        
        self.intentionCollection = intentionCollection
        self.delegate = delegate
    }
    
    private func collect(from intentions: IntentionCollection) {
        let queue = OperationQueue()
        
        for file in intentions.fileIntentions() {
            queue.addOperation {
                self.collectFromFile(file)
            }
        }
        
        queue.waitUntilAllOperationsAreFinished()
    }
    
    private func collectFromFile(_ file: FileGenerationIntention) {
        for function in file.globalFunctionIntentions {
            collectFromFunction(function)
        }
        
        for cls in file.classIntentions {
            collectFromClass(cls)
        }
        
        for cls in file.extensionIntentions {
            collectFromClass(cls)
        }
    }

    private func collectFromFunction(_ function: GlobalFunctionGenerationIntention) {
        guard let body = function.functionBody, let delegate = delegate else {
            return
        }
        
        let context = delegate.makeContext(forFunction: function)
        collectFunctionBody(body, .global(function), context: context)
    }
    
    private func collectFromClass(_ cls: BaseClassIntention) {
        for prop in cls.properties {
            collectProperty(prop)
        }
        
        for ctor in cls.constructors {
            collectInit(ctor)
        }
        
        for method in cls.methods {
            collectMethod(method)
        }
    }
    
    private func collectFunction(_ f: FunctionIntention,
                                 _ intention: FunctionBodyCarryingIntention,
                                 context: Context) {
        
        if let method = f.functionBody {
            collectFunctionBody(method, intention, context: context)
        }
    }
    
    private func collectInit(_ ctor: InitGenerationIntention) {
        guard let delegate = delegate else {
            return
        }
        
        let context = delegate.makeContext(forInit: ctor)
        collectFunction(ctor, .initializer(ctor), context: context)
    }
    
    private func collectMethod(_ method: MethodGenerationIntention) {
        guard let delegate = delegate else {
            return
        }
        
        let context = delegate.makeContext(forMethod: method)
        collectFunction(method, .method(method), context: context)
    }
    
    private func collectProperty(_ property: PropertyGenerationIntention) {
        guard let delegate = delegate else {
            return
        }
        
        switch property.mode {
        case .computed(let getter):
            let context =
                delegate.makeContext(forPropertyGetter: property, getter: getter)
            
            collectFunctionBody(getter, .property(property, isSetter: false), context: context)
            
        case let .property(get, set):
            let getterContext =
                delegate.makeContext(forPropertyGetter: property, getter: get)
            
            collectFunctionBody(get, .property(property, isSetter: false), context: getterContext)
            
            let setterContext =
                delegate.makeContext(forPropertySetter: property, setter: set)
            
            collectFunctionBody(set.body, .property(property, isSetter: true), context: setterContext)
            
        case .asField:
            break
        }
    }
    
    private func collectFunctionBody(_ functionBody: FunctionBodyIntention,
                                     _ intention: FunctionBodyCarryingIntention,
                                     context: Context) {
        
        synchronized(self) {
            items.append(
                FunctionBodyQueueItem(body: functionBody,
                                      intention: intention,
                                      context: context))
        }
    }
    
    public struct FunctionBodyQueueItem {
        public var body: FunctionBodyIntention
        public var intention: FunctionBodyCarryingIntention?
        public var context: Context
        
        public init(body: FunctionBodyIntention,
                    intention: FunctionBodyCarryingIntention?,
                    context: Context) {
            
            self.body = body
            self.intention = intention
            self.context = context
        }
    }
}

/// Describes an intention that is a carrier of a function body.
public enum FunctionBodyCarryingIntention {
    case method(MethodGenerationIntention)
    case initializer(InitGenerationIntention)
    case global(GlobalFunctionGenerationIntention)
    case property(PropertyGenerationIntention, isSetter: Bool)
}

/// An empty funtion body queue implementation which always return an empty
/// context object.
public class EmptyFunctionBodyQueueDelegate: FunctionBodyQueueDelegate {
    public typealias Context = Void
    
    public func makeContext(forFunction function: GlobalFunctionGenerationIntention) {
        
    }
    public func makeContext(forMethod method: MethodGenerationIntention) {
        
    }
    public func makeContext(forInit ctor: InitGenerationIntention) {
        
    }
    public func makeContext(forPropertyGetter property: PropertyGenerationIntention,
                            getter: FunctionBodyIntention) {
        
    }
    public func makeContext(forPropertySetter property: PropertyGenerationIntention,
                            setter: PropertyGenerationIntention.Setter) {
        
    }
}
