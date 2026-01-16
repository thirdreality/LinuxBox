import sys
import time
import os
import lzma

DEBUG = False

if __name__ == '__main__':
    if len(sys.argv) > 1:
        IMAGE = sys.argv[1]
    else:
        print(f'''Usage:
        python3 {sys.argv[0]} <image> [<output>]
        image - input image to repack
        output - output image name to repack. default <image>_repack.img''')
        sys.exit()
    if IMAGE[-3:] == '.xz':
        print("Found compressed image. Uncompress....")
        IMAGE = IMAGE[:-3]
        print(IMAGE)
