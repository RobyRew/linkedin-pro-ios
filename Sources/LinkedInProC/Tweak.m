#import <Orion/Orion.h>
#import <Foundation/Foundation.h>
#import "Tweak.h"

#if THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
#else
#import <libroot.h>
#endif

NSString *LProJBRootPath(NSString *path) {
#if THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(path);
#else
    return JBROOT_PATH_NSSTRING(path);
#endif
}

static void LProWriteBootLog(NSString *message) {
    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"linkedinpro.log"];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [[NSDate date] description], message];
    if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

__attribute__((constructor)) static void LProInit(void) {
    @try {
        // Bring up Orion, then hand control to the Swift Tweak entry
        // (struct LinkedInPro: Tweak). Do not remove orion_init().
        orion_init();
    }
    @catch (NSException *exception) {
        // A failure here must not take LinkedIn down. Record it; the Swift side
        // also installs a non-fatal Orion error handler for hook activation.
        LProWriteBootLog([NSString stringWithFormat:@"orion_init failed: %@ (%@)",
                          exception, exception.reason]);
    }
}
