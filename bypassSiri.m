#import <Foundation/Foundation.h>
#import <Intents/Intents.h>
#import <objc/runtime.h>

static INSiriAuthorizationStatus hook_siriAuthorizationStatus(id self, SEL _cmd) {
    return INSiriAuthorizationStatusDenied;
}

static void hook_requestSiriAuthorization(id self, SEL _cmd, void (^handler)(INSiriAuthorizationStatus)) {
    if (handler) {
        handler(INSiriAuthorizationStatusDenied);
    }
}

static id hook_returnNil(id self, SEL _cmd) {
    return nil;
}

static void replaceClassMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls) return;
    Method m = class_getClassMethod(cls, sel);
    if (m) {
        method_setImplementation(m, newImp);
    }
}

__attribute__((constructor))
static void bypassSiriInit(void) {
    Class prefClass = NSClassFromString(@"INPreferences");
    if (prefClass) {
        replaceClassMethod(prefClass, @selector(siriAuthorizationStatus), (IMP)hook_siriAuthorizationStatus);
        replaceClassMethod(prefClass, @selector(requestSiriAuthorization:), (IMP)hook_requestSiriAuthorization);
        replaceClassMethod(prefClass, @selector(siriLanguageCode), (IMP)hook_returnNil);
        replaceClassMethod(prefClass, NSSelectorFromString(@"sharedPreferences"), (IMP)hook_returnNil);
    }

    Class vocabClass = NSClassFromString(@"INVocabulary");
    if (vocabClass) {
        replaceClassMethod(vocabClass, @selector(sharedVocabulary), (IMP)hook_returnNil);
    }
}
