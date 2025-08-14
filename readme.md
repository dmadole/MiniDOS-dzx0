# MiniDOS-dzx0

This is a file decompressor for MiniDOS that implements the ZX0 algorithm by
Einar Saukas (see https://github.com/einar-saukas/ZX0). This decompressor is
compatible with the output of his C-language compressor.

Build 1 is not highly optimized either for size or speed, but written mostly for
clarify of implementation to serve as a reference model. The command accepts
two filename arguments, the first is the input file, and the second is the
output file.

Build 2 has been optimized somewhat for speed, especially the inner Elias subroutine and the subroutine calling. Depending on the input, it can be about 50% faster than Build 1.
