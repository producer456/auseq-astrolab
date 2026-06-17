#import "ExceptionCatcher.h"

NSError * _Nullable AUSeqTryCatch(void (NS_NOESCAPE ^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSString *desc = exception.reason ?: exception.name ?: @"Unknown Objective-C exception";
        return [NSError errorWithDomain:@"AUSeq.ObjCException"
                                   code:0
                               userInfo:@{ NSLocalizedDescriptionKey: desc }];
    }
}
