
;  Copyright 2023, David S. Madole <david@madole.net>
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.


          ; Definition files

          #include include/bios.inc
          #include include/kernel.inc


          ; Executable header block

            org   1ffah
            dw    begin
            dw    end-begin
            dw    begin

begin:      br    start

            db    8+80h
            db    12
            dw    2025
            dw    1

            db    'See github/dmadole/MiniDOS-dzx0 for more information',0

          ; Parse two command-line arguments, the first will be the input
          ; filename, and the second the output filename.

start:      lda   ra                    ; skip any leading whitespace
            lbz   dousage
            sdi   ' '
            lbdf  start

            ghi   ra                    ; save pointer to first argument
            phi   rf
            glo   ra
            plo   rf
            dec   rf

skipinp:    lda   ra                    ; skip the first argument
            lbz   dousage
            sdi   ' '
            lbnf  skipinp

            dec   ra                    ; zero terminate first argument
            ldi   0
            str   ra
            inc   ra

skipspc:    lda   ra                    ; skip whitespace betweem arguments
            lbz   dousage
            sdi   ' '
            lbdf  skipspc

            ghi   ra                    ; save pointer to second argument
            phi   rd
            glo   ra
            plo   rd
            dec   ra

skipout:    lda   rd                    ; skip the second argument
            lbz   endargs
            sdi   ' '
            lbnf  skipout

            dec   rd                    ; zero terminate second argument
            ldi   0
            str   rd

          ; We have captured two filename arguments, so open the first one,
          ; which will be the input file.

endargs:    ldi   fildes.1              ; pointer to file descriptor
            phi   rd
            ldi   fildes.0
            plo   rd

            ldi   0                     ; plain open with no options
            plo   r7

            sep   scall                 ; open for input, fail if error
            dw    o_open
            lbdf  inpfail

          ; Seek to the end of the file so that we can get the file size. In
          ; order to handle the maximum possible size, we load the input data
          ; up against the top of memory, and decompress to the start of
          ; memory. This way we can overwrite the input data if needed toward
          ; the end of the decompression.

            ldi   0                     ; set seek offset to zero
            phi   r8
            plo   r8
            phi   r7
            plo   r7

            ldi   2                     ; seek relative to end of file
            plo   rc

            sep   scall                 ; move to the end of file now
            dw    o_seek

          ; Next take the size of the file and subtract from the bottom of
          ; the heap to find the address to load the data into.

            ldi   k_heap.1              ; pointer to the address of the heap
            phi   r9
            ldi   k_heap.0
            plo   r9

            sex   r9                    ; use heap pointer address as index

            glo   r7                    ; subtract size from the head address
            inc   r9
            sd
            plo   rb
            plo   rf
            ghi   r7
            dec   r9
            sdb
            phi   rb
            phi   rf

          ; Now seek the file back to the start so we can read from it.

            ldi   0                     ; set seek offset to zero
            phi   r8
            plo   r8
            phi   r7
            plo   r7

            plo   rc                    ; relative to start of file

            sep   scall                 ; seem to start of file
            dw    o_seek

          ; Next read the file data into memory, all in one big chunk.

            ldi   -1                    ; set size to maximum chunk
            phi   rc
            plo   rc

            sep   scall                 ; read from file to memory
            dw    o_read

            sep   scall                 ; close the input file
            dw    o_close

          ; Write the size of the input file in ASCII decimal to a string to
          ; use in outputting a summary message when we are done.

            ghi   rc                    ; get input file read data size
            phi   rd
            glo   rc
            plo   rd

            ldi   inpsize.1             ; pointer to string buffer
            phi   rf
            ldi   inpsize.0
            plo   rf

            sep   scall                 ; convert and write to memory
            dw    f_intout

          ; Setup for the decompressor, we use RF as pointer to the input,
          ; and RD as pointer to the output. The size of the input is not
          ; needed, as the format contains an end-of-file marker.

            ghi   rb                    ; input data pointer
            phi   rf
            glo   rb
            plo   rf

            ldi   end.1                 ; output data pointer
            phi   rd
            ldi   end.0
            plo   rd

          ; The basic algorithm is that from Einar Saukas's standard Z80 ZX0
          ; decompressor, but is completely rewriten due to how different the
          ; 1802 instruction set and architecture is. For a full description
          ; of the ZX0 compression format, see the repository here:
          ;
          ;   https://github.com/einar-saukas/ZX0
          ;
          ; While the decompression algorithm is reasonably simple, the
          ; compression size is complex and expensive. It would run slowly
          ; on the 1802 and take considerably more work to implement.

decompr:    ldi   %10000000             ; empty the elias shift register
            plo   r7

            shl                         ; zero the block length counter
            phi   rc
            plo   rc

            phi   rb                    ; default block copy offset is -1
            plo   rb
            dec   rb

          ; The first block in a stream is always a literal block so the type
          ; bit is not even sent, and we can jump in right at that point. We
          ; just get the block length and copy from source to destination.
          ;
          ; Note that the first bit of an Elias coded number is implied, so
          ; we need to preset the lowest bit pefore getting the rest. Since
          ; RC will always be zero on entry, this can be done with INC only.

literal:    inc   rc                    ; get the length of the block
            sep   scall
            dw    elictrl

copylit:    lda   rf                    ; copy byte from source data
            str   rd
            inc   rd

            dec   rc                    ; loop until all bytes copied
            glo   rc
            lbnz  copylit
            ghi   rc
            lbnz  copylit

          ; A literal is always followed by a copy block. The next input bit 
          ; indicates if is from a new offset or the same offset as last.

            glo   r7                    ; get next bit from input stream
            shl
            plo   r7

            lbdf  newoffs               ; new offset follows if bit is set

          ; Process a copy block by getting the block length and copying from
          ; the output buffer from where the offset points backwards to. Note
          ; that the offset is negative, so we add it to go backwards.

            inc   rc                    ; same offset so just get length
            sep   scall
            dw    elictrl

copyblk:    glo   rb                    ; offset plus position is source
            str   r2
            glo   rd
            add
            plo   r9
            ghi   rb
            str   r2
            ghi   rd
            adc
            phi   r9

copyoff:    lda   r9                     ; copy byte from source data
            str   rd
            inc   rd

            dec   rc                     ; loop until all bytes copied
            glo   rc
            lbnz  copyoff
            ghi   rc
            lbnz  copyoff

          ; After a copy from same offset, the next block must be either a
          ; literal or a copy from new offset, the next bit indicates which.

            glo   r7                     ; check if literal next
            shl
            plo   r7

            lbnf  literal                ; literal block follows if bit clear

          ; The next block is to be copied from a new offset. The value is
          ; stored in two parts, the high bits are Elias-coded, but the low
          ; 7 bits are not and are stored left-aligned in a byte. The lowest
          ; bit of that byte is used to hold the first bit of the length.
          ;
          ; Since the first bit of the Elias part is implied and a negative
          ; number, we need to preload the value with all ones plus a zero
          ; bit. This can be done by DEC, DEC from the starting zero value.

newoffs:    dec   rc                     ; negative value so set to 11111110
            dec   rc

            sep   scall                  ; get the elias-coded offset value
            dw    elictrl

            inc   rc                     ; adjust and test for end of file
            glo   rc
            lbz   endfile

            shrc                         ; shift and combine with low byte
            phi   rb
            lda   rf
            shrc
            plo   rb

            ldi   0                      ; clear since length is positive
            phi   rc
            plo   rc

            inc   rc                     ; get length of the copy block
            sep   scall
            dw    elitest

            inc   rc                     ; adjust offset and copy the block
            lbr   copyblk

          ; When decompression is complete, get the size of the outpu data
          ; but subtracting the start of the buffer from the last address.

endfile:    glo   rd                     ; subtract pointer from start
            smi   end.0
            plo   rc
            plo   rd
            ghi   rd
            smbi  end.1
            phi   rc
            phi   rd

          ; Convert the output size into ASCII decimal into an output string.

            ldi   outsize.1             ; pointer to output size string
            phi   rf
            ldi   outsize.0
            plo   rf

            sep   scall                 ; convert to ascii decimal
            dw    f_intout

          ; Now we can open the output file to write out the data.

            ldi   fildes.1              ; pointer to file descriptor
            phi   rd
            ldi   fildes.0
            plo   rd

            ghi   ra                    ;  pointer to output filename
            phi   rf
            glo   ra
            plo   rf

            ldi   1+2                   ; create file and truncate
            plo   r7

            sep   scall                 ; open file for output or fail
            dw    o_open
            lbdf  outfail

          ; Write the data from memory into the file, all in one chunk.

            ldi   end.1                 ; pointer to start of buffer
            phi   rf
            ldi   end.0
            plo   rf

            sep   scall                 ; write the data to file
            dw    o_write

            sep   scall                 ; close the output file
            dw    o_close

          ; Print the message giving input and output sizes processed.

            ldi   status1.1             ; the part through the input size
            phi   rf
            ldi   status1.0
            plo   rf

            sep   scall                 ; output to console
            dw    o_msg

            ldi   status2.1             ; the part through the output size
            phi   rf
            ldi   status2.0
            plo   rf

            sep   scall                 ; output to console
            dw    o_msg

            ldi   status3.1             ; the trailing part and newline
            phi   rf
            ldi   status3.0
            plo   rf

            sep   scall                 ; output to console
            dw    o_msg

            sep   sret                  ; return to caller

          ; Strings and buffers used for creating the output status message.

status1:    db    'File expanded from '
inpsize:    db    0,0,0,0,0,0

status2:    db    ' to '
outsize:    db    0,0,0,0,0,0

status3:    db    ' bytes.',13,10,0

          ; Subroutine to read an interlaced Elias gamma coded number from
          ; the bit input stream. This keeps a one-byte buffer in R7.0 and
          ; reads from the input pointed to by RF as needed, returning the
          ; resulting decoded number in RC.

elidata:    glo   r7
            shl                         ; get a data bit from buffer
            plo   r7

            glo   rc                    ; shift data bit into result
            shlc
            plo   rc
            ghi   rc
            shlc
            phi   rc

elictrl:    glo   r7                    ; get control bit from buffer
            shl
            plo   r7

            lbnz  elitest               ; if buffer is not empty

            lda   rf                    ; else get another byte
            shlc
            plo   r7

elitest:    lbnf  elidata               ; if bit is zero then end

            sep   sret


          ; Help message output when argument syntax is incorrect.

dousage:    sep   scall
            dw    o_inmsg
            db    'USAGE: dzx0 input output',13,1,0

            sep   sret


          ; Failure message output when input file can't be opened.

inpfail:    sep   scall
            dw    o_inmsg
            db    'ERROR: Can not open input file.',13,1,0

            sep   sret


          ; Failure message output when output file can't be opened.

outfail:    sep   scall
            dw    o_inmsg
            db    'ERROR: Can not open output file.',13,1,0

            sep   sret


          ; File descriptor used for both intput and output files.

fildes:     db    0,0,0,0
            dw    dta
            db    0,0,0,0,0,0,0,0,0,0,0,0,0


          ; Data transfer area that is included in executable header size
          ; but not actually included in executable.

dta:        ds    512

end:        end    begin
