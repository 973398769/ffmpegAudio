//
//  main.m
//  ffmpegAudio2
//
//  Created by EBM on 2022/12/19.
//

#import <Cocoa/Cocoa.h>
#import "DecodeUtil.h"
#import "EncodeUtil.h"

int main(int argc, char *argv[])
{
    EncodeUtil *encoder = [[EncodeUtil alloc] init];
    
    return NSApplicationMain(argc,  (const char **) argv);
}
