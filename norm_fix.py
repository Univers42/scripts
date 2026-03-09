#!/usr/bin/env python3
"""Comprehensive norminette fixer for png_writer library."""

import re
import os
import sys

# ============================================================
# RENAME MAP: camelCase/CamelCase -> snake_case
# ============================================================

TYPE_RENAMES = {
    # Typedef aliases (CamelCase -> t_snake_case)
    'LodePNGColorType': 't_png_color_type',
    'LodePNGColorMode': 't_png_color_mode',
    'LodePNGColorProfile': 't_png_color_profile',
    'LodePNGTime': 't_png_time',
    'LodePNGInfo': 't_png_info',
    'LodePNGCompressSettings': 't_compress_settings',
    'LodePNGDecompressSettings': 't_decompress_settings',
    'LodePNGFilterStrategy': 't_filter_strategy',
    'LodePNGEncoderSettings': 't_encoder_settings',
    'LodePNGDecoderSettings': 't_decoder_settings',
    'LodePNGState': 't_png_state',
    'ColorTree': 't_color_tree',
    'HuffmanTree': 't_huffman_tree',
    'Hash': 't_hash',
    'BPMNode': 't_bpm_node',
    'BPMLists': 't_bpm_lists',
}

FUNC_RENAMES = {
    # Adam7 functions
    'Adam7_deinterlace': 'adam7_deinterlace',
    'Adam7_getpassvalues': 'adam7_getpassvalues',
    'Adam7_interlace': 'adam7_interlace',

    # HuffmanTree functions
    'HuffmanTree_cleanup': 'huffman_tree_cleanup',
    'HuffmanTree_getCode': 'huffman_tree_get_code',
    'HuffmanTree_getLength': 'huffman_tree_get_length',
    'HuffmanTree_init': 'huffman_tree_init',
    'HuffmanTree_make2DTree': 'huffman_tree_make_2d_tree',
    'HuffmanTree_makeFromFrequencies': 'huffman_tree_make_from_freq',
    'HuffmanTree_makeFromLengths': 'huffman_tree_make_from_len',
    'HuffmanTree_makeFromLengths2': 'huffman_tree_make_from_len2',

    # LodePNG init/cleanup functions
    'LodePNGIText_cleanup': 'lodepng_itext_cleanup',
    'LodePNGIText_copy': 'lodepng_itext_copy',
    'LodePNGIText_init': 'lodepng_itext_init',
    'LodePNGText_cleanup': 'lodepng_text_cleanup',
    'LodePNGText_copy': 'lodepng_text_copy',
    'LodePNGText_init': 'lodepng_text_init',
    'LodePNGUnknownChunks_cleanup': 'lodepng_unk_chunks_cleanup',
    'LodePNGUnknownChunks_copy': 'lodepng_unk_chunks_copy',
    'LodePNGUnknownChunks_init': 'lodepng_unk_chunks_init',

    # Bit stream functions
    'addBitToStream': 'add_bit_to_stream',
    'addBitsToStream': 'add_bits_to_stream',
    'addBitsToStreamReversed': 'add_bits_to_stream_rev',
    'addPaddingBits': 'add_padding_bits',
    'readBit': 'read_bit',
    'readBitFromReversedStream': 'read_bit_from_rev_stream',
    'readBitFromStream': 'read_bit_from_stream',
    'readBitsFromReversedStream': 'read_bits_from_rev_stream',
    'readBitsFromStream': 'read_bits_from_stream',
    'setBitOfReversedStream': 'set_bit_of_rev_stream',
    'setBitOfReversedStream0': 'set_bit_of_rev_stream0',
    'removePaddingBits': 'remove_padding_bits',

    # Chunk functions
    'addChunk': 'add_chunk',
    'addChunk_IDAT': 'add_chunk_idat',
    'addChunk_IEND': 'add_chunk_iend',
    'addChunk_IHDR': 'add_chunk_ihdr',
    'addChunk_PLTE': 'add_chunk_plte',
    'addChunk_bKGD': 'add_chunk_bkgd',
    'addChunk_cHRM': 'add_chunk_chrm',
    'addChunk_gAMA': 'add_chunk_gama',
    'addChunk_iCCP': 'add_chunk_iccp',
    'addChunk_iTXt': 'add_chunk_itxt',
    'addChunk_pHYs': 'add_chunk_phys',
    'addChunk_sRGB': 'add_chunk_srgb',
    'addChunk_tEXt': 'add_chunk_text',
    'addChunk_tIME': 'add_chunk_time',
    'addChunk_tRNS': 'add_chunk_trns',
    'addChunk_zTXt': 'add_chunk_ztxt',
    'readChunk_PLTE': 'read_chunk_plte',
    'readChunk_bKGD': 'read_chunk_bkgd',
    'readChunk_cHRM': 'read_chunk_chrm',
    'readChunk_gAMA': 'read_chunk_gama',
    'readChunk_iCCP': 'read_chunk_iccp',
    'readChunk_iTXt': 'read_chunk_itxt',
    'readChunk_pHYs': 'read_chunk_phys',
    'readChunk_sRGB': 'read_chunk_srgb',
    'readChunk_tEXt': 'read_chunk_text',
    'readChunk_tIME': 'read_chunk_time',
    'readChunk_tRNS': 'read_chunk_trns',
    'readChunk_zTXt': 'read_chunk_ztxt',
    'addUnknownChunks': 'add_unknown_chunks',
    'chunkLength': 'chunk_length',
    'chunkName': 'chunk_name',

    # Color functions
    'addColorBits': 'add_color_bits',
    'checkColorValidity': 'check_color_validity',
    'getNumColorChannels': 'get_num_color_channels',
    'getPaletteTranslucency': 'get_palette_translucency',
    'getPixelColorRGBA16': 'get_pixel_color_rgba16',
    'getPixelColorRGBA8': 'get_pixel_color_rgba8',
    'getPixelColorsRGBA8': 'get_pixel_colors_rgba8',
    'getValueRequiredBits': 'get_value_required_bits',
    'rgba16ToPixel': 'rgba16_to_pixel',
    'rgba8ToPixel': 'rgba8_to_pixel',
    'isGrayICCProfile': 'is_gray_icc_profile',
    'isRGBICCProfile': 'is_rgb_icc_profile',

    # Huffman/coding functions
    'addHuffmanSymbol': 'add_huffman_symbol',
    'addLengthDistance': 'add_length_distance',
    'huffmanDecodeSymbol': 'huffman_decode_symbol',
    'countZeros': 'count_zeros',
    'generateFixedDistanceTree': 'gen_fixed_dist_tree',
    'generateFixedLitLenTree': 'gen_fixed_litlen_tree',
    'getHash': 'get_hash',
    'getTreeInflateDynamic': 'get_tree_inflate_dynamic',
    'getTreeInflateFixed': 'get_tree_inflate_fixed',
    'updateHashChain': 'update_hash_chain',
    'writeLZ77data': 'write_lz77_data',
    'encodeLZ77': 'encode_lz77',
    'boundaryPM': 'boundary_pm',

    # Deflate/inflate functions
    'deflateDynamic': 'deflate_dynamic',
    'deflateFixed': 'deflate_fixed',
    'deflateNoCompression': 'deflate_no_compression',
    'inflateHuffmanBlock': 'inflate_huffman_block',
    'inflateNoCompression': 'inflate_no_compression',

    # Filter/scanline functions
    'filterScanline': 'filter_scanline',
    'filterType': 'filter_type',
    'unfilterScanline': 'unfilter_scanline',
    'postProcessScanlines': 'post_process_scanlines',
    'preProcessScanlines': 'pre_process_scanlines',

    # Decode/encode functions
    'decodeGeneric': 'decode_generic',

    # Other functions
    'paethPredictor': 'paeth_predictor',
    'writeSignature': 'write_signature',
    'lodepng_add32bitInt': 'lodepng_add_32bit_int',
    'lodepng_read32bitInt': 'lodepng_read_32bit_int',
    'lodepng_set32bitInt': 'lodepng_set_32bit_int',
}

# Variables that may need renaming
VAR_RENAMES = {
    'filterType': 'filter_type',
    'chunkLength': 'chunk_length',
    'chunkName': 'chunk_name',
}

# Merge all renames (longest first to avoid partial matches)
ALL_RENAMES = {}
ALL_RENAMES.update(TYPE_RENAMES)
ALL_RENAMES.update(FUNC_RENAMES)


def apply_renames(content, renames):
    """Apply word-boundary renames to content."""
    # Sort by length (longest first) to avoid partial matches
    for old, new in sorted(renames.items(), key=lambda x: -len(x[0])):
        content = re.sub(r'\b' + re.escape(old) + r'\b', new, content)
    return content


def fix_file(filepath):
    """Apply all norminette fixes to a single file."""
    with open(filepath, 'r') as f:
        content = f.read()

    original = content

    # 1. Apply renames
    content = apply_renames(content, ALL_RENAMES)

    # Write back
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    return False


def main():
    d = '.'
    if len(sys.argv) > 1:
        d = sys.argv[1]

    count = 0
    for f in sorted(os.listdir(d)):
        if f.endswith('.c') or f.endswith('.h'):
            path = os.path.join(d, f)
            if fix_file(path):
                count += 1
                print(f"Fixed: {f}")
            else:
                print(f"No changes: {f}")
    print(f"\nModified {count} files")


if __name__ == '__main__':
    main()
