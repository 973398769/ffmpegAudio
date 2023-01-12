//
//  ResampleUtil.h
//  ffmpegAudio2
//
//  Created by EBM on 2023/1/9.
//

#import <Foundation/Foundation.h>

@interface ResampleUtil : NSObject

- (void)swrContext:(NSString *)srcFName destFile:(NSString *)destFName;

@end

