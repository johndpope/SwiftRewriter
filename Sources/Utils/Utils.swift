import Cocoa

/// Swift version of Objective-C's @synchronized statement.
/// Do note that differently from Obj-C's version, this closure-based version
/// consumes any 'return/continue/break' statements without affecting the parent
/// function it is enclosed in.
public func synchronized<T>(_ lock: AnyObject, closure: () throws -> T) rethrows -> T {
    objc_sync_enter(lock)
    defer {
        objc_sync_exit(lock)
    }
    
    return try closure()
}

extension Sequence {
    /// - Parameters:
    ///   - key: A closure that should generate the key for the element in the
    /// dictionary.
    ///   - capacity: A minimum capacity to generate the storage arrays with.
    /// Can be used to improve speed, in case it is known that very large arrays
    /// will be created when generating the dictionaries.
    /// - Returns: A dictionary from the sequence keyed by the given closure.
    public func groupBy<T: Hashable>(_ key: (Iterator.Element) -> T, reserving capacity: Int) -> [T: [Iterator.Element]] {
        // Manual containers
        var containers: [[Iterator.Element]] = []
        // Manual key indexes
        var keyIndexes: [T: Int] = [:]
        
        for item in self {
            let field = key(item)
            
            if let index = keyIndexes[field] {
                containers[index].append(item)
            } else {
                let newIndex = containers.count
                var array = [item]
                array.reserveCapacity(capacity)
                containers.append(array)
                
                keyIndexes[field] = newIndex
            }
        }
        
        return flattenMakeshiftDictionary(withArray: containers, mappedBy: keyIndexes)
    }
    
    /// Returns a dictionary containing elements grouped by a specified key,
    /// applying a trasnform on the elements along the way.
    /// Note that the 'key' closure is required to always return the same T key
    /// for the same value passed in, so values can be grouped correctly.
    /// The transform can be used to manipulate values so that keys are removed
    /// from the resulting values on the arrays of each dictionary entry
    public func groupBy<T: Hashable, U>(_ key: (Iterator.Element) -> T, transform: (Iterator.Element) -> U) -> [T: [U]] {
        // Manual containers
        var containers: [[U]] = []
        // Manual key indexes
        var keyIndexes: [T: Int] = [:]
        
        for item in self {
            let field = key(item)
            let newItem = transform(item)
            
            if let index = keyIndexes[field] {
                containers[index].append(newItem)
            } else {
                let newIndex = containers.count
                containers.append([newItem])
                
                keyIndexes[field] = newIndex
            }
        }
        
        return flattenMakeshiftDictionary(withArray: containers, mappedBy: keyIndexes)
    }
    
    /// Returns a dictionary containing elements grouped by a specified key
    /// Note that the 'key' closure is required to always return the same T key
    /// for the same value passed in, so values can be grouped correctly
    public func groupBy<T: Hashable>(_ key: (Iterator.Element) -> T) -> [T: [Iterator.Element]] {
        return groupBy(key, transform: { $0 })
    }
    
    /// Flattens the grouped elements by the least common to most common, with
    /// the count of occurrences along the way
    public func groupByCount<T: Hashable>(_ key: (Iterator.Element) -> T) -> [(value: T, count: Int)] {
        return groupBy(key).sorted { $0.value.count > $1.value.count }.map { tuple in (tuple.key, tuple.value.count) }
    }
    
    /// A group-by where each value for the T-key gets modified by an accumulator
    /// as the key closure returns the same key for a previously existing element
    public func groupByReduced<T: Hashable, U>(_ key: (Iterator.Element) -> T, initial: U, _ nextPartialResult: (U, Iterator.Element) -> U) -> [T: U] {
        // Manual containers
        var containers: [U] = []
        // Manual key indexes
        var keyIndexes: [T: Int] = [:]
        
        for item in self {
            let field = key(item)
            
            if let index = keyIndexes[field] {
                containers[index] = nextPartialResult(containers[index], item)
            } else {
                let newIndex = containers.count
                containers.append(initial)
                
                keyIndexes[field] = newIndex
            }
        }
        
        var dict: [T: U] = [:]
        
        for (key, index) in keyIndexes {
            dict[key] = containers[index]
        }
        
        return dict
    }
}

extension Sequence where Iterator.Element: Hashable {
    
    /// Flattens the grouped elements by the least common to most common, with
    /// the count of occurrences along the way
    public func groupByCount() -> [(value: Iterator.Element, count: Int)] {
        
        // Manual key indexes
        var occurrences: [Iterator.Element: Int] = [:]
        
        for item in self {
            if let count = occurrences[item] {
                occurrences[item] = count + 1
            } else {
                occurrences[item] = 1
            }
        }
        
        return occurrences.sorted { $0.value > $1.value }.map { tuple in (value: tuple.key, count: tuple.value) }
    }
}

extension Sequence {
    
    /// Returns the number of objects in this array that return true when passed
    /// through a given predicate.
    public func count(_ predicate: (Iterator.Element) throws -> Bool) rethrows -> Int {
        var count = 0
        
        for item in self {
            if(try predicate(item)) {
                count += 1
            }
        }
        
        return count
    }
}

/// Flattens a pair of dictionary/array-in-array objects that where used to map
/// a grouping into a single dictionary of arrays.
public func flattenMakeshiftDictionary<T, U>(withArray array: [[T]], mappedBy dict: [U: Int]) -> [U: [T]] {
    // Turn into a dictionary now
    var output: [U: [T]] = [:]
    
    // Create the key-value binding now
    for (key, index) in dict {
        output[key] = Array(array[index])
    }
    
    return output
}

/// Formats a time-stamp in seconds
public func formatTimeInterval(_ interval: TimeInterval, colorized: Bool = true, color: ConsoleColor = .blue) -> String {
    if(interval == 0) {
        return "0s"
    }
    
    let absInterval = abs(interval)
    
    let day: TimeInterval = 24 * 60 * 60
    let hour: TimeInterval = 60 * 60
    let minute: TimeInterval = 60
    
    var output = ""
    
    // Days
    if(absInterval >= day) {
        output += "\(String(format: "%02d", Int(floor(absInterval / day))))d "
    }
    // Hours
    if(absInterval >= hour && floor((absInterval.truncatingRemainder(dividingBy: day)) / hour) > 0) {
        output += "\(String(format: "%02d", Int(floor((absInterval.truncatingRemainder(dividingBy: day)) / hour))))h"
    }
    // Minutes
    if(absInterval >= minute && floor((absInterval.truncatingRemainder(dividingBy: hour)) / minute) > 0) {
        output += "\(String(format: "%02d", Int(floor((absInterval.truncatingRemainder(dividingBy: hour)) / minute))))m"
    }
    // Seconds
    if(floor(absInterval.truncatingRemainder(dividingBy: minute)) > 0) {
        output += "\(String(format: "%d", Int(floor(absInterval.truncatingRemainder(dividingBy: minute)))))s"
    }
    // Milliseconds - milliseconds are always displayed as milliseconds only
    if(absInterval < 1 && absInterval - floor(absInterval) > 0) {
        let milliseconds = floor(absInterval * 1000).truncatingRemainder(dividingBy: 1000)
        output += "\(String(format: "%.2lf", milliseconds / 1000))s"
    }
    
    
    let result = interval < 0 ? "-\(output.trimmingCharacters(in: .whitespacesAndNewlines))" : output.trimmingCharacters(in: .whitespacesAndNewlines)
    
    if(!colorized) {
        return result.stripTerminalColors()
    }
    
    return result.terminalColorize(color)
}
