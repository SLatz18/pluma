#import <Foundation/Foundation.h>

// Shows the system Accessibility prompt and returns the current trust state.
// Called from Swift via the bridging header; a Swift-bridged options
// dictionary segfaults inside HIServices on macOS 26, so the call lives in
// Objective-C where the dictionary is a genuine __NSCFDictionary.
BOOL PlumaRequestAccessibilityPrompt(void);
