import GrammarModels
import Foundation

/// A protocol for objects that perform passes through intentions collected and
/// perform changes and optimizations on them.
public protocol IntentionPass {
    func apply(on intentionCollection: IntentionCollection)
}

/// Gets an array of intention passes to apply before writing the final Swift code.
/// Used by `SwiftRewriter` before it outputs the final intents to `SwiftWriter`.
public enum IntentionPasses {
    public static var passes: [IntentionPass] = [
        FileGroupingIntentionPass(),
        RemoveDuplicatedTypeIntentIntentionPass()
    ]
}

/// From file intentions, remove intentions for interfaces that already have a
/// matching implementation.
/// Must be executed after a pass of `FileGroupingIntentionPass` to avoid dropping
/// @property declarations and the like.
public class RemoveDuplicatedTypeIntentIntentionPass: IntentionPass {
    public func apply(on intentionCollection: IntentionCollection) {
        for file in intentionCollection.intentions(ofType: FileGenerationIntention.self) {
            // Remove from file implementation any class generation intent that came
            // from an @interface
            file.removeTypes(where: { type in
                if !(type.source is ObjcClassInterface || type.source is ObjcClassCategory) {
                    return false
                }
                
                return
                    file.typeIntentions.contains {
                        $0.typeName == type.typeName && $0.source is ObjcClassImplementation
                }
            })
        }
    }
}

public class FileGroupingIntentionPass: IntentionPass {
    public func apply(on intentionCollection: IntentionCollection) {
        // Collect .h/.m pairs
        let intentions =
            intentionCollection.intentions(ofType: FileGenerationIntention.self)
        
        var headers: [FileGenerationIntention] = []
        var implementations: [FileGenerationIntention] = []
        
        for intent in intentions {
            if intent.filePath.hasSuffix(".m") {
                implementations.append(intent)
            } else if intent.filePath.hasSuffix(".h") {
                headers.append(intent)
            }
        }
        
        // For each impl, search for a matching header intent and combine any
        // class intent within
        for implementation in implementations {
            // Merge definitions from within an implementation file first
            mergeDefinitions(in: implementation)
            
            let implFile =
                (implementation.filePath as NSString).deletingPathExtension
            
            guard let header = headers.first(where: { hIntent -> Bool in
                let headerFile =
                    (hIntent.filePath as NSString).deletingPathExtension
                
                return implFile == headerFile
            }) else {
                continue
            }
            
            mergeDefinitions(from: header, into: implementation)
        }
        
        // Remove all header intentions (implementation intentions override them)
        intentionCollection.removeIntentions { (intent: FileGenerationIntention) -> Bool in
            return intent.filePath.hasSuffix(".h")
        }
    }
    
    private func mergeDefinitions(from header: FileGenerationIntention,
                                  into implementation: FileGenerationIntention) {
        let total = header.typeIntentions + implementation.typeIntentions
        
        let groupedTypes = Dictionary(grouping: total, by: { $0.typeName })
        
        for (_, types) in groupedTypes where types.count >= 2 {
            mergeAllTypeDefinitions(in: types)
        }
    }
    
    private func mergeDefinitions(in implementation: FileGenerationIntention) {
        let groupedTypes = Dictionary(grouping: implementation.typeIntentions,
                                      by: { $0.typeName })
        
        for (_, types) in groupedTypes where types.count >= 2 {
            mergeAllTypeDefinitions(in: types)
        }
    }
    
    private func mergeAllTypeDefinitions(in types: [TypeGenerationIntention]) {
        let target = types.reversed().first { $0.source is ObjcClassImplementation } ?? types.last!
        
        for type in types.dropLast() {
            mergeTypes(from: type, into: target)
        }
    }
    
    private func mergeTypes(from first: TypeGenerationIntention, into second: TypeGenerationIntention) {
        // Protocols
        for prot in first.protocols {
            if !second.hasProtocol(named: prot.protocolName) {
                second.addProtocol(prot)
            }
        }
        
        // Instance vars
        for ivar in first.instanceVariables {
            if !second.hasInstanceVariable(named: ivar.name) {
                second.addInstanceVariable(ivar)
            }
        }
        
        // Properties
        for prop in first.properties {
            if !second.hasProperty(named: prop.name) {
                second.addProperty(prop)
            }
        }
        
        // Methods
        // TODO: Figure out how to deal with same-signature selectors properly when
        // trying to find repeated method definitions.
        for method in first.methods {
            if let existing = second.method(withSignature: method.signature) {
                mergeMethod(method, into: existing)
            } else {
                second.addMethod(method)
            }
        }
    }
    
    private func mergeMethod(_ method1: MethodGenerationIntention, into method2: MethodGenerationIntention) {
        if method1.signature.returnTypeNullability != .unspecified &&
            method2.signature.returnTypeNullability == .unspecified {
            method2.signature.returnTypeNullability =
                method1.signature.returnTypeNullability
        }
        
        for (i, p1) in method1.signature.parameters.enumerated() {
            if i >= method2.signature.parameters.count {
                break
            }
            
            let p2 = method2.signature.parameters[i]
            if p2.nullability == .unspecified && p1.nullability != .unspecified {
                method2.signature.parameters[i].nullability = p1.nullability
            }
        }
    }
    
    private struct Pair {
        var header: FileGenerationIntention
        var implementation: FileGenerationIntention
    }
}