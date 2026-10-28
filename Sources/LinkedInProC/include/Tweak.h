#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Maps a jailbreak path through libroot (rootless) or libroothide (roothide)
// so resource lookups resolve under /var/jb. Returns the path unchanged on
// sideload where neither scheme applies.
NSString *LProJBRootPath(NSString *path);

NS_ASSUME_NONNULL_END
