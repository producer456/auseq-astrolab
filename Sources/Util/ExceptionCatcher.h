#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, catching any Objective-C NSException it throws and returning it
/// as an NSError. Swift can't catch ObjC exceptions, so AVFoundation /
/// AUv3-plugin throws (e.g. restoring a bad `fullState`) would otherwise crash
/// the whole app. Wrap those call sites in this.
NSError * _Nullable AUSeqTryCatch(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
