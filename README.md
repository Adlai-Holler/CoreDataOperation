## CoreDataOperation
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)  [![Cocoapods compatible](https://img.shields.io/cocoapods/v/CoreDataOperation.svg)](https://cocoapods.org) [![Cocoapods compatible](https://img.shields.io/cocoapods/p/CoreDataOperation.svg)](https://cocoapods.org)

CoreDataOperation is a fast, safe, flexible operation for updating your core data models. It supports the latest Swift 2.1 syntax, and does all its work in a background managed object context.

### Installation

- Using [CocoaPods](https://cocoapods.org) by adding `pod CoreDataOperation` to your Podfile
- Using [Carthage](https://github.com/Carthage/Carthage) by adding `github "Adlai-Holler/CoreDataOperation"` to your Cartfile.

### How to Use

```swift
let likeOperation = CoreDataOperation<Int>(targetContext: myContext, saveDepth: .ToPersistentStore) { context in
    guard let post = Post.withID(postID, inContext: context) else {
        throw Error.PostWasDeleted
    }
    if post.doILike {
        post.doILike = false
        post.likeCount -= 1
    } else {
        post.doILike = true
        post.likeCount += 1
    }
    post.updatedAt = NSDate()
    return post.likeCount
}
likeOperation.setCompletionBlockWithSuccess( { likeOperation, likeCount in
    // Switch to main queue to update UI
    dispatch_async(dispatch_get_main_queue()) {
        likeCountLabel.text = String(likeCount)
    }
}, failure: { likeOperation, error in
    dispatch_async(dispatch_get_main_queue()) {
        // Show an error.
    }
})
myOperationQueue.addOperation(likeOperation)
```

### Features

- Safe. All operations are confined to a private, background context, so if you get into a bad state, none of your working contexts will be affected.
- Fully asynchronous. No threads are blocked, no two contexts are locked at the same time, and no context is locked for any longer than it absolutely must be.
- Cancelable. The operation checks if it is canceled after each step.
- Modern Swift syntax. Your operation block can throw an error, and it can return a value of any type which can be accessed after the operation is over.
- Lightweight. The body block is disposed of after executing, and the target managed object context is not retained.
- Tests! CoreDataOperation is tested like crazy. 
