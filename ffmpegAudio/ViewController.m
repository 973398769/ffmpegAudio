//
//  ViewController.m
//  ffmpegAudio2
//
//  Created by EBM on 2022/12/19.
//

#import "ViewController.h"
#import "DecodeUtil.h"
#import "EncodeUtil.h"
#import "PCMPlayer.h"

const static NSString *kdeSrcPath = @"deSrcPath";
const static NSString *kdeDestPath = @"deDestPath";
const static NSString *kenSrcPath = @"enSrcPath";
const static NSString *kenDestPath = @"enDestPath";

#pragma mark - TextField
@interface CommonTextField: NSTextField
@end

@implementation CommonTextField

- (instancetype)initWithFrame:(NSRect)frameRect title:(NSString *)title {
    if (self = [super init]) {
        if (title) {
            self.stringValue = title;
        } else {
            self.placeholderString = @"File path";
        }
        [self setFrame:frameRect];
        self.backgroundColor = [NSColor clearColor];
    }
    return self;
}
@end

@interface ViewController()

@property (nonatomic, strong)CommonTextField *deSrcField;
@property (nonatomic, strong)CommonTextField *deDestField;
@property (nonatomic, strong)CommonTextField *enSrcField;
@property (nonatomic, strong)CommonTextField *enDestField;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSImage *iconImage = [NSImage imageNamed:@"AppIcon"];
//    [NSWorkspace sharedWorkspace] setIcon:<#(nullable NSImage *)#> forFile:<#(nonnull NSString *)#> options:<#(NSWorkspaceIconCreationOptions)#>
    NSString *deSrcTitle = [[NSUserDefaults standardUserDefaults] objectForKey:(NSString *)kdeSrcPath];
    self.deSrcField = [[CommonTextField alloc] initWithFrame:NSMakeRect(30, 230, 500, 30) title:deSrcTitle];
    
    NSString *deDestTitle = [[NSUserDefaults standardUserDefaults] objectForKey:(NSString *)kdeDestPath];
    self.deDestField = [[CommonTextField alloc] initWithFrame:NSMakeRect(30, 180, 500, 30) title:deDestTitle];
    
    NSButton *decoderButton = [[NSButton alloc] initWithFrame:NSMakeRect(560, 230, 80, 50)];
    decoderButton.title = @"AAC decoder";
    decoderButton.bordered = NO;
    decoderButton.wantsLayer = YES;
    decoderButton.layer.backgroundColor = [NSColor gridColor].CGColor;
    [decoderButton setAction:@selector(beginDecode:)];
    
    NSButton *clearButtonDe = [[NSButton alloc] initWithFrame:NSMakeRect(560, 180, 80, 30)];
    clearButtonDe.title = @"Clear path";
    clearButtonDe.bordered = NO;
    clearButtonDe.wantsLayer = YES;
    clearButtonDe.layer.backgroundColor = [NSColor colorWithRed:245 green:31 blue:45 alpha:0.8].CGColor;
    [clearButtonDe setAction:@selector(clearPathDecoder:)];
    
    NSButton *playButton = [[NSButton alloc] initWithFrame:NSMakeRect(650, 180, 80, 30)];
    playButton.title = @"Play pcm";
    playButton.bordered = NO;
    playButton.wantsLayer = YES;
    playButton.layer.backgroundColor = [NSColor colorWithRed:100 green:31 blue:100 alpha:0.8].CGColor;
    [playButton setAction:@selector(playPCM:)];
    
    NSString *enSrcTitle = [[NSUserDefaults standardUserDefaults] objectForKey:(NSString *)kenSrcPath];
    self.enSrcField = [[CommonTextField alloc] initWithFrame:NSMakeRect(30, 80, 500, 30) title:enSrcTitle];
    
    NSString *enDestTitle = [[NSUserDefaults standardUserDefaults] objectForKey:(NSString *)kenSrcPath];
    self.enDestField = [[CommonTextField alloc] initWithFrame:NSMakeRect(30, 30, 500, 30) title:enDestTitle];
    
    NSButton *encoderButton = [[NSButton alloc] initWithFrame:NSMakeRect(560, 70, 80, 50)];
    encoderButton.title = @"PCM encoder";
    encoderButton.bordered = NO;
    encoderButton.wantsLayer = YES;
    encoderButton.layer.backgroundColor = [NSColor greenColor].CGColor;
    [encoderButton setAction:@selector(beginEncode:)];
    
    NSButton *clearButtonEn = [[NSButton alloc] initWithFrame:NSMakeRect(560, 20, 80, 30)];
    clearButtonEn.title = @"Clear path";
    clearButtonEn.bordered = NO;
    clearButtonEn.wantsLayer = YES;
    clearButtonEn.layer.backgroundColor = [NSColor colorWithRed:233 green:61 blue:45 alpha:0.8].CGColor;
    [clearButtonEn setAction:@selector(clearPathEncoder:)];
    
    [self.view addSubview:self.deSrcField];
    [self.view addSubview:self.deDestField];
    [self.view addSubview:decoderButton];
    [self.view addSubview:clearButtonDe];
    [self.view addSubview:playButton];
    
    [self.view addSubview:self.enSrcField];
    [self.view addSubview:self.enDestField];
    [self.view addSubview:encoderButton];
    [self.view addSubview:clearButtonEn];
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


- (void)beginDecode:(id)sender {
    NSString *srcPath = self.deSrcField.stringValue;
    NSString *destPath = self.deDestField.stringValue;
    if (srcPath.length == 0 || destPath.length == 0) {
        [self showAlertWindowWithTitle:@"Empty path"];
        return;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:srcPath]) {
        [self showAlertWindowWithTitle:@"Source AAC file is not exist"];
        return;
    }
    
    if ([fm fileExistsAtPath:destPath]) {
        printf("PCM file already exist at path: %s, delete it firstly", [destPath UTF8String]);
        [fm removeItemAtPath:destPath error:NULL];
    }
    
    DecodeUtil *du = [[DecodeUtil alloc] init];
    NSError *error = nil;
    [du decodeAudio:srcPath destPath:destPath error:&error];
    if (error) {
        NSString *errorDes = error.localizedDescription;
        [self showAlertWindowWithTitle:errorDes];
    } else {
        [self showProcessSuccessALertWithTitle:@"Decode success" targetPath:destPath];
    }
}

- (void)clearPathDecoder:(id)sender {
    self.deSrcField.stringValue = @"";
    self.deDestField.stringValue = @"";
}

- (void)beginEncode:(id)sender {
    NSString *srcPath = self.enSrcField.stringValue;
    NSString *destPath = self.enDestField.stringValue;
    if (srcPath.length == 0 || destPath.length == 0) {
        [self showAlertWindowWithTitle:@"Empty path"];
        return;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:srcPath]) {
        [self showAlertWindowWithTitle:@"Source PCM file is not exist"];
        return;
    }
    
    if ([fm fileExistsAtPath:destPath]) {
        printf("AAC file already exist at path: %s, delete it firstly", [destPath UTF8String]);
        [fm removeItemAtPath:destPath error:NULL];
    }
    
    EncodeUtil *encoder = [[EncodeUtil alloc] init];
    NSError *error = nil;
    [encoder encodeFromSrcPath:srcPath toDestPath:destPath error:&error];
    [self cachePaths];
    if (error) {
        NSString *errorDes = error.localizedDescription;
        [self showAlertWindowWithTitle:errorDes];
    }
    else {
        [self showProcessSuccessALertWithTitle:@"Encode success" targetPath:destPath];
    }
}

- (void)clearPathEncoder:(id)sender {
    self.enSrcField.stringValue = @"";
    self.enDestField.stringValue = @"";
}

- (void)showProcessSuccessALertWithTitle:(NSString *)title targetPath:(NSString *)targetPath
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Success";
    alert.informativeText = title;
    NSImage *icon = [NSImage imageNamed:@"successIcon"];
    alert.icon = icon;
    [alert addButtonWithTitle:@"Show In Finder"];
    [alert addButtonWithTitle:@"Got"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [[NSWorkspace sharedWorkspace] selectFile:targetPath inFileViewerRootedAtPath:targetPath];
        }
    }];
}

- (void)showAlertWindowWithTitle:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Error";
    alert.informativeText = title;
    [alert addButtonWithTitle:@"Got"];
    NSImage *icon = [NSImage imageNamed:@"alertIcon"];
    alert.icon = icon;
    alert.alertStyle = NSAlertStyleWarning;
    [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
}

- (void)cachePaths {
    NSString *deSrcPath = self.deSrcField.stringValue;
    if (deSrcPath.length) {
        [[NSUserDefaults standardUserDefaults] setObject:deSrcPath forKey:(NSString *)kdeSrcPath];
    }
    
    NSString *deDestPath = self.deDestField.stringValue;
    if (deDestPath.length) {
        [[NSUserDefaults standardUserDefaults] setObject:deDestPath forKey:(NSString *)kdeDestPath];
    }
    
    NSString *enSrcPath = self.enSrcField.stringValue;
    if (enSrcPath.length) {
        [[NSUserDefaults standardUserDefaults] setObject:enSrcPath forKey:(NSString *)kenSrcPath];
    }
    
    NSString *enDestPath = self.enDestField.stringValue;
    if (enDestPath.length) {
        [[NSUserDefaults standardUserDefaults] setObject:enDestPath forKey:(NSString *)kenDestPath];
    }
}

- (void)playPCM:(id)sender {
    PCMPlayer *player =  [[PCMPlayer alloc] init];
    NSError *error = nil;
    NSString *path = self.deDestField.stringValue;
    [player playPCM:path error:&error];
}

@end
