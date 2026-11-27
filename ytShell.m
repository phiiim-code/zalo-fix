#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>

@interface YTShellManager : NSObject <WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) BOOL isUnlocked;
@property (nonatomic, assign) BOOL keepInMultitask;
@end

@implementation YTShellManager

+ (instancetype)shared {
    static YTShellManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YTShellManager alloc] init];
    });
    return instance;
}

- (void)startObserving {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onAppLaunchOrActivate:) name:UIApplicationDidFinishLaunchingNotification object:nil];
    [nc addObserver:self selector:@selector(onAppLaunchOrActivate:) name:UISceneWillConnectNotification object:nil];
    [nc addObserver:self selector:@selector(onAppLaunchOrActivate:) name:UISceneDidActivateNotification object:nil];
    [nc addObserver:self selector:@selector(onAppLaunchOrActivate:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(onAppResignOrBackground:) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(onAppResignOrBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (UIWindowScene *)activeWindowScene {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState == UISceneActivationStateForegroundActive) {
            return ws;
        }
        if (!fallback) fallback = ws;
    }
    return fallback;
}

- (void)ensureOverlayCreated {
    if (self.overlayWindow) return;

    UIWindowScene *scene = [self activeWindowScene];
    if (!scene) return;

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;

    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"ytShell"];

    NSString *js =
        @"(function(){"
         "if(window.__ytShellReady) return;"
         "window.__ytShellReady = true;"
         "function fire(code, el){"
         "  try{"
         "    if(el){ el.value=''; el.blur(); }"
         "    document.querySelectorAll('video,audio').forEach(function(m){ try{m.pause();}catch(e){} });"
         "    var backBtn = document.querySelector('button[aria-label=\"Back\"], button[aria-label=\"Quay lại\"], .searchbox-back-button');"
         "    if(backBtn){ try{backBtn.click();}catch(e){} }"
         "  }catch(e){}"
         "  try{ window.webkit.messageHandlers.ytShell.postMessage(code); }catch(e){}"
         "}"
         "document.addEventListener('input', function(e){"
         "  var el = e.target;"
         "  if(!el || (el.tagName!=='INPUT' && el.tagName!=='TEXTAREA')) return;"
         "  var v = (el.value || '').trim();"
         "  if(v==='000' || v==='111'){ fire(v, el); }"
         "}, true);"
         "document.addEventListener('submit', function(e){"
         "  var f = e.target;"
         "  if(!f) return;"
         "  var inp = f.querySelector('input[type=\"search\"], input[name=\"search_query\"], input');"
         "  if(!inp) return;"
         "  var v = (inp.value || '').trim();"
         "  if(v==='000' || v==='111'){ e.preventDefault(); e.stopPropagation(); fire(v, inp); }"
         "}, true);"
         "})();";

    WKUserScript *script = [[WKUserScript alloc] initWithSource:js
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [ucc addUserScript:script];
    config.userContentController = ucc;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor systemBackgroundColor];

    WKWebView *wv = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    wv.navigationDelegate = self;
    wv.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:wv];

    [NSLayoutConstraint activateConstraints:@[
        [wv.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
        [wv.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],
        [wv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [wv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor]
    ]];

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://m.youtube.com"]];
    [wv loadRequest:req];

    UIWindow *win = [[UIWindow alloc] initWithWindowScene:scene];
    win.windowLevel = UIWindowLevelAlert + 50;
    win.rootViewController = vc;

    self.webView = wv;
    self.overlayWindow = win;

    if (!self.isUnlocked) {
        [self showOverlay];
    } else {
        self.overlayWindow.hidden = YES;
    }
}

- (void)showOverlay {
    dispatch_block_t work = ^{
        [self ensureOverlayCreated];
        if (!self.overlayWindow) return;

        self.isUnlocked = NO;

        // Tắt bàn phím của Zalo trước khi phủ YouTube lên
        UIWindowScene *scene = self.overlayWindow.windowScene ?: [self activeWindowScene];
        for (UIWindow *w in scene.windows) {
            if (w != self.overlayWindow) {
                [w endEditing:YES];
            }
        }

        // Nếu WebView lỡ đang ở trang kết quả tìm kiếm mã bí mật thì đưa về trang chủ
        NSString *curURL = self.webView.URL.absoluteString ?: @"";
        if ([curURL containsString:@"search_query=000"] || [curURL containsString:@"search_query=111"]) {
            [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://m.youtube.com"]]];
        }

        self.overlayWindow.hidden = NO;
        [self.overlayWindow makeKeyAndVisible];
        [CATransaction flush];
    };

    if ([NSThread isMainThread]) work();
    else dispatch_async(dispatch_get_main_queue(), work);
}

- (void)unlockWithKeepMultitask:(BOOL)keep {
    dispatch_block_t work = ^{
        self.keepInMultitask = keep;
        self.isUnlocked = YES;

        [self.overlayWindow endEditing:YES];
        self.overlayWindow.hidden = YES;

        // Trả lại quyền nhận cảm ứng & bàn phím cho cửa sổ Zalo
        UIWindowScene *scene = self.overlayWindow.windowScene ?: [self activeWindowScene];
        for (UIWindow *w in scene.windows) {
            if (w != self.overlayWindow && !w.hidden && w.windowLevel == UIWindowLevelNormal) {
                [w makeKeyAndVisible];
                break;
            }
        }
    };

    if ([NSThread isMainThread]) work();
    else dispatch_async(dispatch_get_main_queue(), work);
}

- (void)onAppLaunchOrActivate:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureOverlayCreated];
        if (!self.isUnlocked && self.overlayWindow) {
            self.overlayWindow.hidden = NO;
            [self.overlayWindow makeKeyAndVisible];
        }
    });
}

- (void)onAppResignOrBackground:(NSNotification *)note {
    if (!self.keepInMultitask) {
        [self showOverlay];
    }
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"ytShell"]) return;
    NSString *code = [NSString stringWithFormat:@"%@", message.body];
    if ([code isEqualToString:@"000"]) {
        [self unlockWithKeepMultitask:NO];
    } else if ([code isEqualToString:@"111"]) {
        [self unlockWithKeepMultitask:YES];
    }
}

#pragma mark - WKNavigationDelegate (Dự phòng nếu bấm nút Tìm kiếm)

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (url) {
        NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *item in comps.queryItems) {
            if ([item.name isEqualToString:@"search_query"]) {
                NSString *v = [item.value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([v isEqualToString:@"000"]) {
                    decisionHandler(WKNavigationActionPolicyCancel);
                    [self unlockWithKeepMultitask:NO];
                    return;
                } else if ([v isEqualToString:@"111"]) {
                    decisionHandler(WKNavigationActionPolicyCancel);
                    [self unlockWithKeepMultitask:YES];
                    return;
                }
            }
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

@end

__attribute__((constructor))
static void ytShellInit(void) {
    [[YTShellManager shared] startObserving];
}
