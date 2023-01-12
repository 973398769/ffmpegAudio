//
//  decodeUtil.h
//  ffmpegAudio2
//
//  Created by EBM on 2023/1/2.
//

#import <Foundation/Foundation.h>

@interface DecodeUtil : NSObject

- (void)decodeAudio:(NSString *)srcPath destPath:(NSString *)destPath error:(NSError **)error;

 @end

