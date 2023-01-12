//
//  decodeUtil.m
//  ffmpegAudio2
//
//  Created by EBM on 2023/1/2.
//

#import "DecodeUtil.h"
#import <Cocoa/Cocoa.h>

#ifdef __cplusplus
extern "C" {
#endif

#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/opt.h"

#ifdef __cplusplus
};
#endif

// 输入缓冲区的大小
#define AUDIO_INBUF_SIZE 20480
// 需要再次读取输入文件数据的阈值
#define AUDIO_REFILL_THRESH 4096

static const AVCodec *codec = NULL;
static AVCodecContext *codec_ctx = NULL;
static AVCodecParserContext *parser = NULL;
// AVPacket: 存放解码前的数据
static AVPacket *pkt = NULL;
// AVFrame: 存放解码前的数据
static AVFrame *frame = NULL;
static FILE *srcFile = NULL;
const char *srcFileName = NULL;
static FILE *dstFile = NULL;
const char *dstFileName = NULL;
static const NSString *errorDomain = @"decoderError";

@implementation DecodeUtil

- (void)decodeAudio:(NSString *)srcPath destPath:(NSString *)destPath error:(NSError **)error {
    const char* aacDecoderName = "AAC";
    
    if (!srcPath || !destPath) {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Empty path" forKey:NSLocalizedDescriptionKey]];
        goto end;
    }
    
    srcFileName = [srcPath UTF8String];
    dstFileName = [destPath UTF8String];
    if (![self openFile:srcFileName dstFilePath:dstFileName]) {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Open file failed" forKey:NSLocalizedDescriptionKey]];
        goto end;
    }
    
    if (![self initAudioDecoder:(char *)aacDecoderName withError:error])
        goto end;
    
    if (![self audioDecoding:error])
        goto end;
end:
    [self destroyAudioDecoder];
    [self closeFile:srcFile];
    [self closeFile:dstFile];
}

- (BOOL)initAudioDecoder:(char *)audioCodecName withError:(NSError **)error {
    if (strcasecmp(audioCodecName, "AAC") == 0) {
//        codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
        codec = avcodec_find_decoder_by_name("libfdk_aac");
    } else {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Unknown decoder name" forKey:NSLocalizedDescriptionKey]];
        return NO;
    }
    
    if (!codec){
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Cannot find AAC decoder" forKey:NSLocalizedDescriptionKey]];
        return NO;
    }
    parser = av_parser_init(codec->id);
    if (!parser) {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Cannot init CodecParserContext" forKey:NSLocalizedDescriptionKey]];
        return NO;
    }
    
    codec_ctx = avcodec_alloc_context3(codec);
    if (!codec_ctx) {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Cannot init CodecContext" forKey:NSLocalizedDescriptionKey]];
        return NO;
    }
    
    int32_t result = avcodec_open2(codec_ctx, codec, NULL);
    if (result < 0) {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Cannot open CodecContext" forKey:NSLocalizedDescriptionKey]];
        return NO;
    }
    
    frame = av_frame_alloc();
    if (!frame) {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Cannot init AVFrame" forKey:NSLocalizedDescriptionKey]];
        return NO;
    }
    
    pkt = av_packet_alloc();
    if (!pkt)
    {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Cannot init AVPacket" forKey:NSLocalizedDescriptionKey]];
        return NO;
    }
    
    return YES;
}

- (BOOL)audioDecoding:(NSError **)error {
    // AV_INPUT_BUFFER_PADDING_SIZE: 用来防止读取过多而产生越界行为
    uint8_t inbuf[AUDIO_INBUF_SIZE + AV_INPUT_BUFFER_PADDING_SIZE] = { 0 };
    // 指向存放 inbuf 的指针
    uint8_t *data = NULL;
    // 每次读取数据的大小
    int32_t dataSize = 0;
    while (![self endOfFile:srcFile]) {
        if ([self readDataToBuf:inbuf size:AUDIO_INBUF_SIZE outSize:&dataSize])
        {
            // 每次从文件中读取数据，都需要将 data 指回 inbuf 首元素
            data = inbuf;
            while (dataSize > 0) {
                // 解析器处理数据，并放到 pkt 中; result: 已经解码的数据
               int result2 = av_parser_parse2(parser,
                                          codec_ctx,
                                          &pkt->data,
                                          &pkt->size,
                                          data,
                                          dataSize,
                                          AV_NOPTS_VALUE,
                                          AV_NOPTS_VALUE,
                                          0);
                if (result2 < 0) {
                    *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: av_parser_parse2 failed.\n" forKey:NSLocalizedDescriptionKey]];
                    fprintf(stderr, "Error: av_parser_parse2 failed.\n");
                    return NO;
                }

                // 跳过已经解析好的数据
                data += result2;
                // 减去已经解析过的数据（因为从文件中读取的数据，解析器不一定一次性能处理完）
                dataSize -= result2;
                
                // 解码
                if (pkt->size) {
    //                printf("Parsed packet size: %d.\n", pkt->size);
                    [self decodePacket:NO];
                }
            }
        } else {
            *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: readDataToBuf:size:outSize: failed.\n" forKey:NSLocalizedDescriptionKey]];
            fprintf(stderr, "Error: readDataToBuf:size:outSize: failed.\n");
            return NO;
        }
    }
    // 冲刷缓冲区
    [self decodePacket:YES];
    [self printFileSize];
    [self getAudioFormat:codec_ctx];
    return YES;
}

- (int32_t)getAudioFormat:(AVCodecContext *)codecCtx {
    int ret = 0;
    const char *fmt;
    enum AVSampleFormat sfmt = codecCtx->sample_fmt;
    if (av_sample_fmt_is_planar(sfmt)) {
        const char *packed = av_get_sample_fmt_name(sfmt);
        printf("Warning: the sample format the decoder produced is planar ");
        printf("%s", packed);
        printf(", This example will output the first channel only.\n");
        sfmt = av_get_packed_sample_fmt(sfmt);
    }

//    int n_channels = codec_ctx->channels;
    
    if ((ret = [self getFormatFromSampleFmt:&fmt sampleFmt:sfmt]) < 0) {
        return -1;
    }

//  std::cout << "Play command: ffpay -f " << std::string(fmt) << " -ac "
//            << n_channels << " -ar " << codec_ctx->sample_rate << " output.pcm"
//            << std::endl;
  return 0;
}

- (int)getFormatFromSampleFmt:(const char **)fmt sampleFmt:(enum AVSampleFormat)sampleFmt {
    int i;
    struct sample_fmt_entry {
        enum AVSampleFormat sample_fmt;
        const char *fmt_be, *fmt_le;
    } sample_fmt_entries[] = {
        {AV_SAMPLE_FMT_U8, "u8", "u8"},
        {AV_SAMPLE_FMT_S16, "s16be", "s16le"},
        {AV_SAMPLE_FMT_S32, "s32be", "s32le"},
        {AV_SAMPLE_FMT_FLT, "f32be", "f32le"},
        {AV_SAMPLE_FMT_DBL, "f64be", "f64le"},
    };
    *fmt = NULL;

    for (i = 0; i < FF_ARRAY_ELEMS(sample_fmt_entries); i++) {
        struct sample_fmt_entry *entry = &sample_fmt_entries[i];
        if (sampleFmt == entry->sample_fmt) {
            *fmt = AV_NE(entry->fmt_be, entry->fmt_le);
            return 0;
        }
    }
    
    printf("sample format %s is not supported as output format.\n", av_get_sample_fmt_name(sampleFmt));
    return -1;
}

- (BOOL)decodePacket:(BOOL)flushing {
    int32_t result = avcodec_send_packet(codec_ctx, flushing ? NULL : pkt);
    if (result < 0) {
        fprintf(stderr, "Error: faile to send packet, result: %d\n", result);
        return NO;
    }
    while (result >= 0) {
        result = avcodec_receive_frame(codec_ctx, frame);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
            return NO;
        } else if (result < 0) {
            fprintf(stderr, "Error: faile to receive frame, result: %d\n", result);
            return NO;
        }
        
        if (flushing) {
            printf("Flushing:");
        }
        
        result = [self writeSamplesToPcm:frame codecCtx:codec_ctx];
        
        if (result < 0) {
            fprintf(stderr, "Error: write samples to pcm failed.\n");
            return NO;
        }
//        printf("frame->nb_samples: %d\n", frame->nb_samples);
//        printf("frame->channels: %d\n", frame->channels);
  }
  return YES;
}

- (BOOL)writeSamplesToPcm:(AVFrame *)frame codecCtx:(AVCodecContext*)codecCtx {
    // 单个声道一个样本的大小（假如是两声道就是一个 L，或者是一个 R）
    int singleSize = av_get_bytes_per_sample(codecCtx->sample_fmt);
    // 所有声道单个样本的总大小（假如是两声道就是一个LR）
    int totalSize = codecCtx->channels *singleSize;
    if (singleSize < 0) {
        fprintf(stderr, "Error: failed to calculate data size");
        return NO;
    }
    
    if (av_sample_fmt_is_planar(codecCtx->sample_fmt)) {// PCM 是 planar
        /*
         假如 PCM 是这样：LLLLLRRRRR
         那单个声道的样本数就是：frame->nb_samples，这里等于5;
         那声道数就是2
         */
        for (int sampleIdx = 0; sampleIdx < frame->nb_samples; sampleIdx++) {// for:单个声道的样本数
            for (int channelIdx = 0; channelIdx < codecCtx->channels; channelIdx++) {//for: 声道数
                // 写入frame的顺序是：先左声道写入一个样本L；再右声道写入一个样本R；然后移动指针，指向下个样本；然后重复上面的操作，直到文件尾部
                fwrite(frame->data[channelIdx] + sampleIdx *singleSize, 1, singleSize, dstFile);
            }
        }
    } else {// PCM 是 packed
        size_t size = fwrite(frame->data[0], 1, totalSize *frame->nb_samples, dstFile);
        
    }
    return YES;
}

// 释放资源
- (void)destroyAudioDecoder {
    av_parser_close(parser);
    avcodec_free_context(&codec_ctx);
    av_frame_free(&frame);
    av_packet_free(&pkt);
}

#pragma mark - File related
- (BOOL)readDataToBuf:(uint8_t *)buf size:(int32_t)size outSize:(int32_t *)outSize {
    size_t readSize = fread(buf, 1, size, srcFile);
    if (readSize == 0) {
        fprintf(stderr, "Error: readDataToBuf:size:outSize: failed.\n");
        return NO;
    }
    *outSize = (int32_t)readSize;
    return YES;
}

/// 判断文件到达尾部
- (int)endOfFile:(FILE *)file {
    if (!file) {
        fprintf(stderr, "Error: file is empty.\n");
        return 1;
    }
    return feof(file);
}

- (BOOL)openFile:(const char*)srcFilePath dstFilePath:(const char *)dstFilePath {
    if (strlen(srcFilePath) == 0 || strlen(dstFilePath) == 0) {
        return NO;
    }
    [self closeFile:srcFile];
    [self closeFile:dstFile];
    
    srcFile = fopen(srcFilePath, "rb");
    if (srcFile == NULL) {
        return NO;
    }
    dstFile = fopen(dstFilePath, "wb");
    if (dstFile == NULL) {
        return NO;
    }
    
    return YES;
}

- (void)closeFile:(FILE *)file {
    if (file) {
        fclose(file);
        file = NULL;
    }
}

- (void)printFileSize {
    NSString *path = [NSString stringWithUTF8String:dstFileName];
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:path]) {
        NSLog(@"Decoded PCM file size: %llu bytes", [[manager attributesOfItemAtPath:path error:nil] fileSize]);
    }
}
@end
