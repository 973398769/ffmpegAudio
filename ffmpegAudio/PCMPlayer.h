//
//  PCMPlayer.h
//  ffmpegAudio2
//
//  Created by EBM on 2023/1/13.
//

#import <Foundation/Foundation.h>

@interface PCMPlayer : NSObject

- (void)playPCM:(NSString*)filePath error:(NSError **)error;
    
@end

