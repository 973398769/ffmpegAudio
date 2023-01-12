//
//  EncodeUtil.h
//  ffmpegAudio2
//
//  Created by EBM on 2023/1/9.
//

#import <Foundation/Foundation.h>

@interface EncodeUtil : NSObject

- (void)encodeFromSrcPath:(NSString *)srcPath toDestPath:(NSString *)destPath error:(NSError **)error;

@end

