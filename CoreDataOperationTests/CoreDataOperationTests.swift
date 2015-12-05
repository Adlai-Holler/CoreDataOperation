//
//  CoreDataOperationTests.swift
//  CoreDataOperationTests
//
//  Created by Adlai Holler on 12/4/15.
//  Copyright © 2015 Adlai Holler. All rights reserved.
//

import XCTest
import CoreData
@testable import CoreDataOperation

private var store: NSPersistentStoreCoordinator!
private var rootContext: NSManagedObjectContext!
private var workingContext: NSManagedObjectContext!
private let queue: NSOperationQueue = {
    let q = NSOperationQueue()
    q.name = "TestQueue"
    return q
}()

private func allEmployees(context: NSManagedObjectContext) -> Set<Employee> {
    let req = NSFetchRequest(entityName: "Employee")
    let employees = try! context.executeFetchRequest(req) as! [Employee]
    return Set(employees)
}

class CoreDataOperationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        store = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel.mergedModelFromBundles([NSBundle(forClass: self.dynamicType)])!)
        try! store.addPersistentStoreWithType(NSInMemoryStoreType, configuration: nil, URL: nil, options: nil)

        rootContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        rootContext.persistentStoreCoordinator = store

        workingContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        workingContext.parentContext = rootContext

        workingContext.performBlockAndWait {
            let e1 = NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: workingContext) as! Employee
            e1.name = "Harold"

            let e2 = NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: workingContext) as! Employee
            e2.name = "Kumar"

            let d1 = NSEntityDescription.insertNewObjectForEntityForName("Department", inManagedObjectContext: workingContext) as! Department
            d1.name = "(Unemployed)"

            d1.employees.unionInPlace([e1, e2])

            try! workingContext.obtainPermanentIDsForObjects(Array(workingContext.insertedObjects))
            try! workingContext.save()
        }

        rootContext.performBlockAndWait {
            try! rootContext.save()
        }
    }

    override func tearDown() {
        queue.cancelAllOperations()
        workingContext = nil
        rootContext = nil
        store = nil
        super.tearDown()
    }

    func testThatHarnessWorks() {
        workingContext.performBlockAndWait {
            XCTAssertEqual(Set(allEmployees(workingContext).map { $0.name }), Set(["Harold", "Kumar"]))
        }
    }

    func testThatSuccessfulOperationSuceeds() {
        let op = CoreDataOperation<String>(targetContext: workingContext) { ctx in
            let e2 = NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: ctx) as! Employee
            e2.name = "Silent Bob"
            return "Example Result"
        }
        let expectation = expectationWithDescription("Operation Completion")
        op.completionBlock = {
            workingContext.performBlockAndWait {
                XCTAssert(allEmployees(workingContext).contains { $0.name == "Silent Bob" })
            }
            rootContext.performBlockAndWait {
                XCTAssert(allEmployees(rootContext).contains { $0.name == "Silent Bob" })
            }
            XCTAssertEqual(op.result, "Example Result")
            XCTAssertNil(op.error)
            XCTAssertNil(op.errorSavingAncestor)
            expectation.fulfill()
        }
        queue.addOperation(op)
        waitForExpectationsWithTimeout(1, handler: nil)
    }

    func testThatErrorSavingScratchContextIsReported() {
        let op = CoreDataOperation<String>(targetContext: workingContext) { ctx in
            NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: ctx) as! Employee
            return "Example Result You Won't See"
        }
        let expectation = expectationWithDescription("Operation Completion")
        op.completionBlock = {
            XCTAssertNotNil(op.error)
            XCTAssertNil(op.result)
            XCTAssertNil(op.errorSavingAncestor)
            expectation.fulfill()
        }
        queue.addOperation(op)
        waitForExpectationsWithTimeout(1, handler: nil)
    }

    func testThatCancelledOperationIsCancelled() {
        let lock = NSLock()
        let op = CoreDataOperation<String>(targetContext: workingContext) { ctx in
            lock.lock()
            lock.unlock()
            let e2 = NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: ctx) as! Employee
            e2.name = "Silent Bob"
            return "Example Result"
        }
        op.completionBlock = {
            XCTFail()
        }
        lock.lock()
        queue.addOperation(op)
        op.cancel()
        lock.unlock()
        sleep(1)
        XCTAssert(op.cancelled)
        workingContext.performBlockAndWait {
            XCTAssert(!allEmployees(workingContext).contains { $0.name == "Silent Bob" })
        }
        rootContext.performBlockAndWait {
            XCTAssert(!allEmployees(rootContext).contains { $0.name == "Silent Bob" })
        }
        XCTAssertEqual(op.error as? NSError, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil))
        XCTAssertNil(op.errorSavingAncestor)
        XCTAssertNil(op.result)
    }

    func testThatOneDeepOperationOnlySavesOneDeep() {
        let op = CoreDataOperation<String>(targetContext: workingContext, saveDepth: .OnlyScratchContext) { ctx in
            let e2 = NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: ctx) as! Employee
            e2.name = "Silent Bob"
            return "Example Result"
        }
        let expectation = expectationWithDescription("Operation Completion")
        op.completionBlock = {
            workingContext.performBlockAndWait {
                XCTAssert(workingContext.hasChanges)
                XCTAssert(allEmployees(workingContext).contains { $0.name == "Silent Bob" })
            }
            rootContext.performBlockAndWait {
                XCTAssert(!rootContext.hasChanges)
                XCTAssert(!allEmployees(rootContext).contains { $0.name == "Silent Bob" })
            }
            XCTAssertEqual(op.result, "Example Result")
            XCTAssertNil(op.error)
            XCTAssertNil(op.errorSavingAncestor)
            expectation.fulfill()
        }
        queue.addOperation(op)
        waitForExpectationsWithTimeout(1, handler: nil)
    }

    func testThatTwoDeepOperationOnlySavesTwoDeep() {
        let op = CoreDataOperation<String>(targetContext: workingContext, saveDepth: .ScratchAndTargetContext) { ctx in
            let e2 = NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: ctx) as! Employee
            e2.name = "Silent Bob"
            return "Example Result"
        }
        let expectation = expectationWithDescription("Operation Completion")
        op.completionBlock = {
            workingContext.performBlockAndWait {
                XCTAssert(!workingContext.hasChanges)
                XCTAssert(allEmployees(workingContext).contains { $0.name == "Silent Bob" })
            }
            rootContext.performBlockAndWait {
                XCTAssert(rootContext.hasChanges)
                XCTAssert(allEmployees(rootContext).contains { $0.name == "Silent Bob" })
            }
            XCTAssertEqual(op.result, "Example Result")
            XCTAssertNil(op.error)
            XCTAssertNil(op.errorSavingAncestor)
            expectation.fulfill()
        }
        queue.addOperation(op)
        waitForExpectationsWithTimeout(1, handler: nil)
    }

    func testThatAllTheWayOperationSavesAllTheWay() {
        let op = CoreDataOperation<String>(targetContext: workingContext, saveDepth: .ToPersistentStore) { ctx in
            let e2 = NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: ctx) as! Employee
            e2.name = "Silent Bob"
            return "Example Result"
        }
        let expectation = expectationWithDescription("Operation Completion")
        op.completionBlock = {
            workingContext.performBlockAndWait {
                XCTAssert(!workingContext.hasChanges)
                XCTAssert(allEmployees(workingContext).contains { $0.name == "Silent Bob" })
            }
            rootContext.performBlockAndWait {
                XCTAssert(!rootContext.hasChanges)
                XCTAssert(allEmployees(rootContext).contains { $0.name == "Silent Bob" })
            }
            XCTAssertEqual(op.result, "Example Result")
            XCTAssertNil(op.error)
            XCTAssertNil(op.errorSavingAncestor)
            expectation.fulfill()
        }
        queue.addOperation(op)
        waitForExpectationsWithTimeout(1, handler: nil)
    }

    func testThatErrorSavingAncestorIsReportedCorrectlyFromTarget() {
        workingContext.performBlockAndWait {
            // Put an invalid employee into the working context so the save will fail.
            NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: workingContext) as! Employee
        }
        let op = CoreDataOperation<String>(targetContext: workingContext, saveDepth: .ScratchAndTargetContext) { ctx in
            let e2 = NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: ctx) as! Employee
            e2.name = "Silent Bob"
            return "Example Result"
        }
        let expectation = expectationWithDescription("Operation Completion")
        op.completionBlock = {
            workingContext.performBlockAndWait {
                XCTAssert(workingContext.hasChanges)
                XCTAssert(allEmployees(workingContext).contains { $0.name == "Silent Bob" })
            }
            XCTAssertEqual(op.result, "Example Result")
            XCTAssertNil(op.error)
            XCTAssertNotNil(op.errorSavingAncestor)
            expectation.fulfill()
        }
        queue.addOperation(op)
        waitForExpectationsWithTimeout(1, handler: nil)
    }

    func testThatErrorSavingAncestorIsReportedCorrectlyFromGrandTarget() {
        rootContext.performBlockAndWait {
            // Put an invalid employee into the root context so the save will fail.
            NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: rootContext) as! Employee
        }
        let op = CoreDataOperation<String>(targetContext: workingContext, saveDepth: .ToPersistentStore) { ctx in
            let e2 = NSEntityDescription.insertNewObjectForEntityForName("Employee", inManagedObjectContext: ctx) as! Employee
            e2.name = "Silent Bob"
            return "Example Result"
        }
        let expectation = expectationWithDescription("Operation Completion")
        op.completionBlock = {
            workingContext.performBlockAndWait {
                XCTAssert(!workingContext.hasChanges)
                XCTAssert(allEmployees(workingContext).contains { $0.name == "Silent Bob" })
            }
            rootContext.performBlockAndWait {
                XCTAssert(rootContext.hasChanges)
                XCTAssert(allEmployees(rootContext).contains { $0.name == "Silent Bob" })
            }
            XCTAssertEqual(op.result, "Example Result")
            XCTAssertNil(op.error)
            XCTAssertNotNil(op.errorSavingAncestor)
            expectation.fulfill()
        }
        queue.addOperation(op)
        waitForExpectationsWithTimeout(1, handler: nil)
    }

    func testThatErrorThrownFromBodyIsReported() {
        let op = CoreDataOperation<String>(targetContext: workingContext) { ctx in
            throw NSError(domain: NSCocoaErrorDomain, code: 1337, userInfo: nil)
        }
        let expectation = expectationWithDescription("Operation Completion")
        op.completionBlock = {
            XCTAssertNil(op.result)
            XCTAssertEqual(op.error as? NSError, NSError(domain: NSCocoaErrorDomain, code: 1337, userInfo: nil))
            XCTAssertNil(op.errorSavingAncestor)
            expectation.fulfill()
        }
        queue.addOperation(op)
        waitForExpectationsWithTimeout(1, handler: nil)
    }

    func testThatOperationIsCancelledIfTargetContextIsDeallocated() {
        weak var target: NSManagedObjectContext?
        let op: CoreDataOperation<Void>
        do {
            let strongTarget = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
            target = strongTarget
            strongTarget.parentContext = workingContext
            op = CoreDataOperation(targetContext: target!) { ctx in
                XCTFail()
            }
        }
        XCTAssertNil(target)
        op.completionBlock = {
            XCTFail()
        }
        queue.addOperation(op)
        sleep(1)
        XCTAssert(op.cancelled)
        XCTAssertNil(op.result)
        XCTAssertEqual(op.error as? NSError, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil))
        XCTAssertNil(op.errorSavingAncestor)
    }
    
}
