
import Foundation
import CoreData

let debugLogging = false

func Log(message: String) {
    if debugLogging {
        NSLog(message)
    }
}

public enum CoreDataOperationSaveDepth: Int {
    case OnlyScratchContext = 0
    case ScratchAndTargetContext = 1
    case ToPersistentStore = 100
}
/**
The default value is `.ToPersistentStore`. This value is not thread-safe,
so don't go changing it all over the place.

FIXME: Make this static when static stored vars are supported on generics.
*/
public var CoreDataOperationDefaultSaveDepth: CoreDataOperationSaveDepth = .ToPersistentStore

public final class CoreDataOperation<Result>: NSOperation {

    public let saveDepth: CoreDataOperationSaveDepth
    public let obtainPermanentObjectIDs: Bool

    static var canceledError: NSError {
        return NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
    }

    internal var body: ((NSManagedObjectContext) throws -> Result)?

    public internal(set) weak var targetContext: NSManagedObjectContext?

    /**
     * The error thrown from the operation body block,
     * or thrown by core data while saving the scratch context.
     * Note: You must not read this property until the operation is finished.
     * Note: Exactly 1 of `error` and `result` will be non-nil.
     * Note: If there is an error saving an ancestor of the scratch
     * context, this property will be nil.
     * You may check the `errorSavingAncestor` property in this case.
     */
    internal(set) var error: ErrorType?

    /**
     * The result returned by the operation body block.
     * Note: You must not read this property until the operation is finished.
     * Note: Exactly 1 of `error` and `result` will be non-nil.
     */
    internal(set) var result: Result?

    /**
     * The error encountered while saving an ancestor context, if you
     * provided a save depth other than `OnlyScratchContext`, and
     * if one occured.
     * Note: You must not read this property until the operation is finished.
     */
    internal(set) var errorSavingAncestor: ErrorType?

    internal var _finished = Atomic(false)
    internal var _executing = Atomic(false)

    /**
     * Initialize a new operation.

     * - Parameter targetContext: The managed object context to update. The operation
     * will create a "scratch context" as a child of this context, and the work will be
     * done in there.
     * Note: The operation does not retain this context. If it is deallocated
     * before the operation begins, the operation will cancel itself.
     * Parameter obtainPermanentObjectIDs: Should this operation attempt to obtain
     * permanent object IDs for objects inserted during the operation body? The default
     * value is `true`.
     * Parameter saveDepth: How far up the hierarchy of managed object contexts should this operation
     * save? See `CoreDataOperationDefaultSaveDepth`.
     * Parameter body: The work to be done. The managed object context passed into this block
     * will be a private child context, owned by this operation, of the `targetContext`.
     * Note: You must work with objects in the provided context.
     */
    public init(targetContext: NSManagedObjectContext, obtainPermanentObjectIDs: Bool = true, saveDepth: CoreDataOperationSaveDepth = CoreDataOperationDefaultSaveDepth, body: (NSManagedObjectContext) throws -> Result) {
        self.saveDepth = saveDepth
        self.obtainPermanentObjectIDs = obtainPermanentObjectIDs
        self.body = body
        self.targetContext = targetContext
    }

    public func setCompletionHandlerWithSuccess(success: ((CoreDataOperation<Result>, Result) -> Void)? = nil, failure: ((CoreDataOperation<Result>, ErrorType) -> Void)? = nil) {
        completionBlock = { [unowned self] in
            if let result = self.result {
                success?(self, result)
            } else if let error = self.error {
                failure?(self, error)
            } else {
                fatalError("\(self) completed with no result and no error.")
            }
        }
    }

    override public var asynchronous: Bool {
        return true
    }

    override public var finished: Bool {
        return _finished.value
    }

    override public var executing: Bool {
        return _executing.value
    }

    override public func start() {
        willChangeValueForKey("isExecuting")
        _executing.value = true
        didChangeValueForKey("isExecuting")

        guard let targetContext = targetContext else {
            cancel()
            finishWithError(CoreDataOperation.canceledError, result: nil)
            return
        }

        Log("Starting \(self)")
        let child = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        child.parentContext = targetContext
        child.performBlock {
            self.executeInContext(child)
        }
    }

    internal func executeInContext(context: NSManagedObjectContext) {
        guard !cancelled else {
            dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
                self.finishWithError(CoreDataOperation.canceledError, result: nil)
            }
            return
        }

        do {

            // Run body block then dispose of it.
            Log("\(self) will execute body.")
            let result = try body!(context)
            self.body = nil

            // Obtain permanent IDs if we need to.
            if obtainPermanentObjectIDs && !context.insertedObjects.isEmpty {
                Log("\(self) will obtain permanent IDs.")
                try context.obtainPermanentIDsForObjects(Array(context.insertedObjects))
            }

            // Save the scratch context.
            Log("\(self) will save scratch context.")
            try context.save()

            // Asynchronously save up the chain as needed.
            CoreDataOperation.saveUpTheChain(context.parentContext,
                maxDepth: saveDepth.rawValue,
                canceled: { [weak self] in
                    self?.cancelled ?? true
                },
                completion: { [weak self] errorOrNil in
                    self?.errorSavingAncestor = errorOrNil
                    self?.finishWithError(nil, result: result)
                })
        } catch let error {
            Log("\(self) caught error \(error)")
            finishWithError(error, result: nil)
        }

    }

    internal func finishWithError(error: ErrorType?, result: Result?) {
        Log("\(self) did finish with error \(error), result \(result), ancestorError \(errorSavingAncestor).")
        self.result = result
        self.error = error

        willChangeValueForKey("isExecuting")
        willChangeValueForKey("isFinished")
        _executing.value = false
        _finished.value = true
        didChangeValueForKey("isFinished")
        didChangeValueForKey("isExecuting")
    }

    // MARK: Static Helpers

    /// The completion block will always be executed on an arbitrary queue, so we don't hold the lock on any context during it.
    internal static func saveUpTheChain(context: NSManagedObjectContext?, maxDepth: Int, canceled: () -> Bool, completion: (ErrorType? -> Void)) {
        guard let context = context where maxDepth > 0 && !canceled() else {
            Log("CoreDataOperation reached the end of save chain.")
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)) {
                completion(nil)
            }
            return
        }

        context.performBlock {
            guard !canceled() else {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)) {
                    completion(nil)
                }
                return
            }

            do {
                Log("CoreDataOperation will save \(context)")
                try context.save()

                saveUpTheChain(context.parentContext, maxDepth: maxDepth - 1, canceled: canceled, completion: completion)
            } catch let error {
                Log("CoreDataOperation caught error: \(error)")
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)) {
                    completion(error)
                }
            }
        }
    }
}
