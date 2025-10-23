//
//  DNSDemoViewController.m
//  AlicloudHttpDNSTestDemo
//
//  @author Created by Claude Code on 2025-10-05
//

#import "DemoViewController.h"
#import "DemoResolveModel.h"
#import "DemoLogViewController.h"
#import "DemoHttpdnsScenario.h"

@interface DemoViewController () <DemoHttpdnsScenarioDelegate>

@property (nonatomic, strong) DemoHttpdnsScenario *scenario;
@property (nonatomic, strong) DemoHttpdnsScenarioConfig *scenarioConfig;
@property (nonatomic, strong) DemoResolveModel *model;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;

@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UISegmentedControl *ipTypeSeg;

@property (nonatomic, strong) UISwitch *swHTTPS;
@property (nonatomic, strong) UISwitch *swPersist;
@property (nonatomic, strong) UISwitch *swReuse;

@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *ttlLabel;

@property (nonatomic, strong) UITextView *resultTextView;

@property (nonatomic, weak) DemoLogViewController *presentedLogVC;

@end

@implementation DemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HTTPDNS Demo";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.scenario = [[DemoHttpdnsScenario alloc] initWithDelegate:self];
    self.model = self.scenario.model;
    self.scenarioConfig = [[DemoHttpdnsScenarioConfig alloc] init];
    [self buildUI];
    [self reloadUIFromModel:self.model];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"日志" style:UIBarButtonItemStylePlain target:self action:@selector(onShowLog)];
}

- (void)buildUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.stack = [[UIStackView alloc] init];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12.0;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:16],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-16],
        [self.stack.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-32]
    ]];

    UIStackView *row1 = [self labeledRow:@"Host"];
    self.hostField = [[UITextField alloc] init];
    self.hostField.placeholder = @"www.aliyun.com";
    self.hostField.text = self.scenarioConfig.host;
    self.hostField.borderStyle = UITextBorderStyleRoundedRect;
    [row1 addArrangedSubview:self.hostField];
    [self.stack addArrangedSubview:row1];

    UIStackView *row2 = [self labeledRow:@"IP Type"];
    self.ipTypeSeg = [[UISegmentedControl alloc] initWithItems:@[@"IPv4", @"IPv6", @"Both"]];
    self.ipTypeSeg.selectedSegmentIndex = [self segmentIndexForIpType:self.scenarioConfig.ipType];
    [self.ipTypeSeg addTarget:self action:@selector(onIPTypeChanged:) forControlEvents:UIControlEventValueChanged];
    [row2 addArrangedSubview:self.ipTypeSeg];
    [self.stack addArrangedSubview:row2];

    UIStackView *opts = [[UIStackView alloc] init];
    opts.axis = UILayoutConstraintAxisHorizontal;
    opts.alignment = UIStackViewAlignmentCenter;
    opts.distribution = UIStackViewDistributionFillEqually;
    opts.spacing = 8;
    [self.stack addArrangedSubview:opts];

    [opts addArrangedSubview:[self switchItem:@"HTTPS" action:@selector(onToggleHTTPS:) out:&_swHTTPS]];
    [opts addArrangedSubview:[self switchItem:@"持久化" action:@selector(onTogglePersist:) out:&_swPersist]];
    [opts addArrangedSubview:[self switchItem:@"复用过期" action:@selector(onToggleReuse:) out:&_swReuse]];

    self.swHTTPS.on = self.scenarioConfig.httpsEnabled;
    self.swPersist.on = self.scenarioConfig.persistentCacheEnabled;
    self.swReuse.on = self.scenarioConfig.reuseExpiredIPEnabled;
    [self applyOptionSwitches];

    UIStackView *actions = [[UIStackView alloc] init];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 12;
    actions.distribution = UIStackViewDistributionFillEqually;
    [self.stack addArrangedSubview:actions];

    UIButton *btnAsync = [self filledButton:@"Resolve (SyncNonBlocing)" action:@selector(onResolveAsync)];
    UIButton *btnSync = [self borderButton:@"Resolve (Sync)" action:@selector(onResolveSync)];
    [actions addArrangedSubview:btnAsync];
    [actions addArrangedSubview:btnSync];

    UIStackView *info = [self labeledRow:@"Info"];
    self.elapsedLabel = [self monoLabel:@"elapsed: - ms"];
    self.ttlLabel = [self monoLabel:@"ttl v4/v6: -/- s"];
    [info addArrangedSubview:self.elapsedLabel];
    [info addArrangedSubview:self.ttlLabel];
    [self.stack addArrangedSubview:info];
    if (@available(iOS 11.0, *)) { [self.stack setCustomSpacing:24 afterView:info]; }


    UILabel *resultTitle = [[UILabel alloc] init];
    resultTitle.text = @"结果";
    resultTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.stack addArrangedSubview:resultTitle];

    self.resultTextView = [[UITextView alloc] init];
    self.resultTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.resultTextView.editable = NO;
    if (@available(iOS 13.0, *)) {
        self.resultTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        self.resultTextView.textColor = [UIColor labelColor];
    } else {
        self.resultTextView.font = [UIFont systemFontOfSize:12];
        self.resultTextView.textColor = [UIColor blackColor];
    }
    self.resultTextView.backgroundColor = [UIColor clearColor];
    self.resultTextView.textContainerInset = UIEdgeInsetsMake(8, 12, 8, 12);
    [self.stack addArrangedSubview:self.resultTextView];
    [self.resultTextView.heightAnchor constraintEqualToConstant:320].active = YES;


}

- (UIStackView *)labeledRow:(NSString *)title {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8.0;
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    [label.widthAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
    [row addArrangedSubview:label];
    return row;
}

- (UILabel *)monoLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    if (@available(iOS 13.0, *)) {
        l.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    } else {
        l.font = [UIFont systemFontOfSize:12];
    }
    return l;
}

- (UIButton *)filledButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.backgroundColor = [UIColor systemBlueColor];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.layer.cornerRadius = 8;
    [b.heightAnchor constraintEqualToConstant:44].active = YES;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIButton *)borderButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor systemBlueColor].CGColor;
    b.layer.cornerRadius = 8;
    [b.heightAnchor constraintEqualToConstant:44].active = YES;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)switchItem:(NSString *)title action:(SEL)sel out:(UISwitch * __strong *)outSwitch {
    UIStackView *box = [[UIStackView alloc] init];
    box.axis = UILayoutConstraintAxisVertical;
    box.alignment = UIStackViewAlignmentCenter;
    UILabel *l = [[UILabel alloc] init];
    l.text = title;
    UISwitch *s = [[UISwitch alloc] init];
    [s addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [box addArrangedSubview:s];
    [box addArrangedSubview:l];
    if (outSwitch != NULL) {
        *outSwitch = s;
    }
    return box;
}

- (NSInteger)segmentIndexForIpType:(HttpdnsQueryIPType)ipType {
    switch (ipType) {
        case HttpdnsQueryIPTypeIpv4: { return 0; }
        case HttpdnsQueryIPTypeIpv6: { return 1; }
        default: { return 2; }
    }
}

#pragma mark - Actions

- (void)onIPTypeChanged:(UISegmentedControl *)seg {
    HttpdnsQueryIPType type = HttpdnsQueryIPTypeBoth;
    switch (seg.selectedSegmentIndex) {
        case 0: type = HttpdnsQueryIPTypeIpv4; break;
        case 1: type = HttpdnsQueryIPTypeIpv6; break;
        default: type = HttpdnsQueryIPTypeBoth; break;
    }
    self.model.ipType = type;
    self.scenarioConfig.ipType = type;
    [self.scenario applyConfig:self.scenarioConfig];
}

- (void)applyOptionSwitches {
    self.scenarioConfig.httpsEnabled = self.swHTTPS.isOn;
    self.scenarioConfig.persistentCacheEnabled = self.swPersist.isOn;
    self.scenarioConfig.reuseExpiredIPEnabled = self.swReuse.isOn;
    [self.scenario applyConfig:self.scenarioConfig];
}

- (void)onToggleHTTPS:(UISwitch *)s { [self applyOptionSwitches]; }
- (void)onTogglePersist:(UISwitch *)s { [self applyOptionSwitches]; }
- (void)onToggleReuse:(UISwitch *)s { [self applyOptionSwitches]; }

- (void)onResolveAsync {
    [self.view endEditing:YES];
    NSString *host = self.hostField.text.length > 0 ? self.hostField.text : @"www.aliyun.com";
    self.model.host = host;
    self.scenarioConfig.host = host;
    [self.scenario applyConfig:self.scenarioConfig];
    [self.scenario resolveSyncNonBlocking];
}

- (void)onResolveSync {
    [self.view endEditing:YES];
    NSString *host = self.hostField.text.length > 0 ? self.hostField.text : @"www.aliyun.com";
    self.model.host = host;
    self.scenarioConfig.host = host;
    [self.scenario applyConfig:self.scenarioConfig];
    [self.scenario resolveSync];
}

- (void)onShowLog {
    DemoLogViewController *logVC = [DemoLogViewController new];
    [logVC setInitialText:[self.scenario logSnapshot]];
    self.presentedLogVC = logVC;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:logVC];
    nav.modalPresentationStyle = UIModalPresentationAutomatic;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)reloadUIFromModel:(DemoResolveModel *)model {
    self.model = model;
    if (![self.hostField isFirstResponder]) {
        self.hostField.text = model.host;
    }
    NSInteger segIndex = [self segmentIndexForIpType:model.ipType];
    if (self.ipTypeSeg.selectedSegmentIndex != segIndex) {
        self.ipTypeSeg.selectedSegmentIndex = segIndex;
    }
    self.elapsedLabel.text = [NSString stringWithFormat:@"elapsed: %.0f ms", model.elapsedMs];
    self.ttlLabel.text = [NSString stringWithFormat:@"ttl v4/v6: %.0f/%.0f s", model.ttlV4, model.ttlV6];
    self.resultTextView.text = [self buildJSONText:model];
}


- (NSString *)buildJSONText:(DemoResolveModel *)model {
    NSString *ipTypeStr = @"both";
    switch (model.ipType) {
        case HttpdnsQueryIPTypeIpv4: { ipTypeStr = @"ipv4"; break; }
        case HttpdnsQueryIPTypeIpv6: { ipTypeStr = @"ipv6"; break; }
        default: { ipTypeStr = @"both"; break; }
    }
    NSDictionary *dict = @{
        @"host": model.host ?: @"",
        @"ipType": ipTypeStr,
        @"elapsedMs": @(model.elapsedMs),
        @"ttl": @{ @"v4": @(model.ttlV4), @"v6": @(model.ttlV6) },
        @"ipv4": model.ipv4s ?: @[],
        @"ipv6": model.ipv6s ?: @[]
    };
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&err];
    if (data == nil || err != nil) {
        return [NSString stringWithFormat:@"{\n  \"error\": \"%@\"\n}", err.localizedDescription ?: @"json serialize failed"];
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - DemoHttpdnsScenarioDelegate

- (void)scenario:(DemoHttpdnsScenario *)scenario didUpdateModel:(DemoResolveModel *)model {
    [self reloadUIFromModel:model];
}

- (void)scenario:(DemoHttpdnsScenario *)scenario didAppendLogLine:(NSString *)line {
    if (self.presentedLogVC != nil) {
        [self.presentedLogVC appendLine:line];
    }
}

@end
