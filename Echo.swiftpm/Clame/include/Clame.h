#ifndef CLAME_H
#define CLAME_H


#include <stddef.h>
#include <stdint.h>


#ifdef __cplusplus
extern "C" {
#endif


// ================================================
// LAME opaque encoder
// ================================================

typedef struct lame_global_struct lame_global_flags;

typedef lame_global_flags *lame_t;


// ================================================
// Encoder lifecycle
// ================================================

lame_t lame_init(void);

int lame_close(
    lame_t gfp
);


// ================================================
// Encoder configuration
// ================================================

int lame_set_in_samplerate(
    lame_t gfp,
    int in_samplerate
);

int lame_set_num_channels(
    lame_t gfp,
    int num_channels
);

int lame_set_brate(
    lame_t gfp,
    int bitrate
);

int lame_set_quality(
    lame_t gfp,
    int quality
);

int lame_init_params(
    lame_t gfp
);


// ================================================
// Encoding
// ================================================

int lame_encode_buffer_interleaved(
    lame_t gfp,
    short int pcm[],
    int num_samples,
    unsigned char *mp3buf,
    int mp3buf_size
);


int lame_encode_flush(
    lame_t gfp,
    unsigned char *mp3buf,
    int size
);


// ================================================
// ID3 metadata
// ================================================

void id3tag_init(
    lame_t gfp
);


void id3tag_add_v2(
    lame_t gfp
);


void id3tag_set_title(
    lame_t gfp,
    const char *title
);


void id3tag_set_artist(
    lame_t gfp,
    const char *artist
);


void id3tag_set_album(
    lame_t gfp,
    const char *album
);


int id3tag_set_albumart(
    lame_t gfp,
    const char *image,
    size_t size
);


#ifdef __cplusplus
}
#endif


#endif
