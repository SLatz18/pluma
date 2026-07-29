#import "AccessibilityPrompt.h"
#import <ApplicationServices/ApplicationServices.h>

BOOL PlumaRequestAccessibilityPrompt(void) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}
