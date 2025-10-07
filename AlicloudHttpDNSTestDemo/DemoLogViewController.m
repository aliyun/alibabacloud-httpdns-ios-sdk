//
//  DemoLogViewController.m
//  AlicloudHttpDNSTestDemo
//
//  @author Created by Claude Code on 2025-10-05
//

#import "DemoLogViewController.h"

@interface DemoLogViewController ()

@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy) NSString *pendingInitialText;

@end

@implementation DemoLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"日志";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    if (@available(iOS 13.0, *)) {
        self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    } else {
        self.textView.font = [UIFont systemFontOfSize:12];
    }
    [self.view addSubview:self.textView];
    [NSLayoutConstraint activateConstraints:@[[self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8], [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12], [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12], [self.textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8]]];

    if (self.pendingInitialText.length > 0) {
        self.textView.text = self.pendingInitialText;
        self.pendingInitialText = nil;
    }

    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(onClose)];
    self.navigationItem.leftBarButtonItem = close;
}

- (void)onClose {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setInitialText:(NSString *)text {
    if (self.isViewLoaded) {
        self.textView.text = text ?: @"";
        [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length, 0)];
    } else {
        self.pendingInitialText = [text copy];
    }
}

- (void)appendLine:(NSString *)line {
    // 当日志较多时，直接追加可避免重排整块文本
    if (self.isViewLoaded) {
        NSString *append = line ?: @"";
        if (append.length > 0) {
            self.textView.text = [self.textView.text stringByAppendingString:append];
            [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length, 0)];
        }
    }
}

@end
