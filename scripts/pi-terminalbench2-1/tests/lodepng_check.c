#include "lodepng.cpp"
#include <assert.h>

int main(int argc, char** argv) {
  unsigned widths[] = {1, 7, 28, 33}, depths[] = {1, 2, 4, 8, 16};
  unsigned wi, di, interlace;
  unsigned char* decoded = 0;
  unsigned w, h;
  assert(argc == 2);
  assert(lodepng_decode32_file(&decoded, &w, &h, argv[1]) == 0);
  assert(w == 28 && h == 28);
  assert(lodepng_crc32(decoded, (size_t)w * h * 4) == 1640082992u);
  free(decoded);

  for(wi = 0; wi < 4; ++wi) for(di = 0; di < 5; ++di) for(interlace = 0; interlace < 2; ++interlace) {
    LodePNGState state;
    unsigned char raw[2178], *png = 0;
    size_t rawsize, pngsize, i, bits;
    lodepng_state_init(&state);
    state.info_raw.colortype = state.info_png.color.colortype = LCT_GREY;
    state.info_raw.bitdepth = state.info_png.color.bitdepth = depths[di];
    state.info_png.interlace_method = interlace;
    state.encoder.auto_convert = 0;
    w = widths[wi]; h = widths[wi];
    bits = (size_t)w * h * depths[di];
    rawsize = lodepng_get_raw_size(w, h, &state.info_raw);
    for(i = 0; i < rawsize; ++i) raw[i] = (unsigned char)(i * 37u + 11u);
    if(bits % 8) raw[rawsize - 1] &= (unsigned char)(255u << (8 - bits % 8));
    assert(lodepng_encode(&png, &pngsize, raw, w, h, &state) == 0);
    decoded = 0;
    assert(lodepng_decode_memory(&decoded, &w, &h, png, pngsize, LCT_GREY, depths[di]) == 0);
    assert(memcmp(raw, decoded, rawsize) == 0);
    printf("%u %u %u %u\n", w, depths[di], interlace, lodepng_crc32(png, pngsize));
    free(decoded); free(png); lodepng_state_cleanup(&state);
  }

  {
    unsigned passw[7], passh[7];
    size_t filtered[8], padded[8], unpadded[8];
    unsigned char header[33] = {137,80,78,71,13,10,26,10, 0,0,0,13, 73,72,68,82,
                              32,0,0,0, 32,0,0,0, 16,6,0,0,1, 0,0,0,0};
    assert(sizeof(size_t) >= 8);
    Adam7_getpassvalues(passw, passh, filtered, padded, unpadded, 131072, 131072, 8);
    assert(padded[7] == ((size_t)1 << 34));
    assert(unpadded[7] == ((size_t)1 << 34));
    lodepng_chunk_generate_crc(header + 8);
    decoded = 0;
    assert(lodepng_decode_memory(&decoded, &w, &h, header, sizeof(header), LCT_RGBA, 16) == 92);
    assert(decoded == 0);
  }
  return 0;
}
