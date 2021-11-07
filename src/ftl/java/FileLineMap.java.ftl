[#ftl strict_vars=true]
[#--
/* Copyright (c) 2020, 2021 Jonathan Revusky, revusky@javacc.com
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright notices,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name Jonathan Revusky
 *       nor the names of any contributors may be used to endorse 
 *       or promote products derived from this software without specific prior written 
 *       permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */
 --]
/* Generated by: ${generated_by}. ${filename} */

[#if grammar.parserPackage?has_content]
package ${grammar.parserPackage};
[/#if]

import java.io.IOException;
import java.io.Reader;
import java.util.Arrays;
import java.util.BitSet;
import java.util.HashMap;
import java.util.Map;
import java.nio.charset.Charset;

/**
 * Rather bloody-minded implementation of a class to store the input and keep 
 * track of where the lines are. Generally speaking, it takes care of all the
 * pre-lexical details, like character encodings, code units vs. code points,
 * and also (if the case applies) keeping track of which regions of the input
 * are turned off by a preprocessor. 
 * N.B. This class is not (any longer) some kind of input stream. It just 
 * pretends that it is by having these #readChar, #backup and #forward methods.
 */
@SuppressWarnings("unused")
public class FileLineMap {

    // Munged content, possibly replace unicode escapes, tabs, or CRLF with LF.
    private final CharSequence content;
    // Typically a filename, I suppose.
    private String inputSource;
    // A list of offsets of the beginning of lines
    private final int[] lineOffsets;

    // The starting line and column, usually 1,1
    // that is used to report a file position 
    // in 1-based line/column terms
    private int startingLine, startingColumn;

    // The offset in the internal buffer to the very
    // next character that the readChar method returns
    private int bufferPosition;


    // If this is set, it determines 
    // which lines in the file are actually processed.
    private BitSet parsedLines;

    /**
     * This is used in conjunction with having a preprocessor.
     * We set which lines are actually parsed lines and the 
     * unset ones are ignored. 
     * @param parsedLines a #java.util.BitSet that holds which lines
     * are parsed (i.e. not ignored)
     */
    public void setParsedLines(BitSet parsedLines) {
        this.parsedLines = parsedLines;
    }
    
    
    /**
     * This constructor may not be used much soon. Pretty soon all the generated API
     * will tend to use #java.nio.file.Path rather than java.io classes like Reader
     * @param inputSource the lookup name of this FileLineMap
     * @param reader The input to read from
     * @param startingLine location info used in error reporting, this is 1 typically, assuming
     * we started reading at the start of the file.
     * @param startingColumn location info used in error reporting, this is 1 typically, assuming
     * we started reading at the start of the file.
     *//*
    public FileLineMap(String inputSource, Reader reader, int startingLine, int startingColumn) {
        this(inputSource, readToEnd(reader), startingLine, startingColumn);
    }*/

    /**
     * Constructor that takes a String or string-like object as the input
     * @param inputSource the lookup name of this FileLineMap
     * @param content The input to read from
     */
    public FileLineMap(String inputSource, CharSequence content) {
        this(inputSource, content, 1, 1);
    }

    /**
     * Constructor that takes a String or string-like object as the input
     * @param inputSource the lookup name of this FileLineMap
     * @param content The input to read from
     * @param startingLine location info used in error reporting, this is 1 typically, assuming
     * we started reading at the start of the file.
     * @param startingColumn location info used in error reporting, this is 1 typically, assuming
     * we started reading at the start of the file.
     */
    public FileLineMap(String inputSource, CharSequence content, int startingLine, int startingColumn) {
        setInputSource(inputSource);
        this.content = content;
        this.lineOffsets = createLineOffsetsTable(this.content);
        this.startingLine = startingLine;
        this.startingColumn = startingColumn;
    }

    /**
     * @return the line number from the absolute offset passed in as a parameter
     */
    int getLineFromOffset(int pos) {
        if (pos >= content.length()) {
            if (content.charAt(content.length()-1) == '\n') {
                return startingLine + lineOffsets.length;
            }
            return startingLine + lineOffsets.length-1;
        }
        int bsearchResult = Arrays.binarySearch(lineOffsets, pos);
        if (bsearchResult>=0) {
            return startingLine + bsearchResult;
        }
        return startingLine-(bsearchResult+2);
    }

    int getCodeUnitColumnFromOffset(int pos) {
        if (pos >= content.length()) return 1;
        int line = getLineFromOffset(pos)-startingLine;
        return 1+pos-lineOffsets[line];
    }

    int getCodePointColumnFromOffset(int pos) {
        if (pos >= content.length()) return 1;
        if (Character.isLowSurrogate(content.charAt(pos))) --pos;
        int line = getLineFromOffset(pos)-startingLine;
        int lineStart = lineOffsets[line];
        int numSupps = numSupplementaryCharactersInRange(lineStart, pos);
        return 1+pos-lineOffsets[line]-numSupps;
    }
    
    // Now some methods to fulfill the functionality that used to be in that
    // SimpleCharStream class
    /**
     * Backup a certain number of characters
     * This method is dead simple by design and does not handle any of the messiness
     * with column numbers relating to tabs or unicode escapes. 
     * @param amount the number of characters (code points) to backup.
     */
    public void backup(int amount) {
        for (int i=0; i<amount; i++) {
            char ch = content.charAt(--bufferPosition);
            if (bufferPosition > 0 && Character.isLowSurrogate(ch)) {
                if (Character.isHighSurrogate(content.charAt(bufferPosition-1))) {
                    --bufferPosition;
                }
            }
            if (ch == '\n') skipUnparsedLinesBackward();
        }
    }
    
    void forward(int amount) {
        for (int i=0; i<amount; i++) {
            boolean eol = content.charAt(bufferPosition) == '\n';
            ++bufferPosition;
            char ch = content.charAt(bufferPosition);
            if (Character.isLowSurrogate(ch)) {
                if (Character.isHighSurrogate(content.charAt(bufferPosition-1))) {
                    ++bufferPosition;
                }
            }
            if (eol) skipUnparsedLinesForward();
        }
    }

    int getEndColumn() {
        return getCodePointColumnFromOffset(bufferPosition-1);
    }
    
    int readChar() {
        if (bufferPosition >= content.length()) {
            return -1;
        }
        char ch = content.charAt(bufferPosition++);
        if (Character.isHighSurrogate(ch) && bufferPosition < content.length()) {
            char nextChar = content.charAt(bufferPosition);
            if (Character.isLowSurrogate(nextChar)) {
                ++bufferPosition;
                return Character.toCodePoint(ch, nextChar);
            }
        }
        if (ch == '\n') {
            skipUnparsedLinesForward();
        }
        return ch;
    }

    /**
      * If our current bufferPosition corresponds
      * to a line that is to be skipped,
      * we scan forward to the next line that is not skipped
      */
    private void skipUnparsedLinesForward() {
        if (parsedLines == null) return;
        int line = getLineFromOffset(bufferPosition);
        int nextParsedLine = parsedLines.nextSetBit(line);
        if (nextParsedLine == -1) {
            bufferPosition = content.length();
        }
        else if (nextParsedLine != line) {
            bufferPosition = lineOffsets[nextParsedLine-startingLine];
        }
    }

    /**
     * If our current bufferPosition corresponds
     * to a line that is to be skipped,
     * we scan forward to the next line that is not skipped
     */
    private void skipUnparsedLinesBackward() {
        if (parsedLines == null) return;
        int  line = getLineFromOffset(bufferPosition);
        int prevParsedLine = parsedLines.previousSetBit(line);
        if (prevParsedLine == -1) {
            skipUnparsedLinesForward();
        }
        else if (prevParsedLine != line) {
            bufferPosition = lineOffsets[1+prevParsedLine-startingLine] -1;
        }
    }

    int getLine() {
        return getLineFromOffset(bufferPosition);
    }

    int getColumn() {
        return getCodePointColumnFromOffset(bufferPosition);
    }

    int getBufferPosition() {return bufferPosition;}

    int getEndLine() {
        int line = getLineFromOffset(bufferPosition);
        int column = getCodePointColumnFromOffset(bufferPosition);
        return column == 1 ? line -1 : line;
    }

    // But there is no goto in Java!!!

    void goTo(int offset) {
        this.bufferPosition = offset;
        skipUnparsedLinesForward();
    }

    /**
     * @return the line length in code _units_
     */ 
    private int getLineLength(int lineNumber) {
        int startOffset = getLineStartOffset(lineNumber);
        int endOffset = getLineEndOffset(lineNumber);
        return 1+endOffset - startOffset;
    }

    /**
     * The number of supplementary unicode characters in the specified 
     * offset range. The range is expressed in code units
     */
    private int numSupplementaryCharactersInRange(int start, int end) {
        int result =0;
        while (start < end-1) {
            if (Character.isHighSurrogate(content.charAt(start++))) {
                if (Character.isLowSurrogate(content.charAt(start))) {
                    start++;
                    result++;
                }
            }
        }
        return result;
    }

    /**
     * The offset of the start of the given line. This is in code units
     */
    private int getLineStartOffset(int lineNumber) {
        int realLineNumber = lineNumber - startingLine;
        if (realLineNumber <=0) {
            return 0;
        }
        if (realLineNumber >= lineOffsets.length) {
            return content.length();
        }
        return lineOffsets[realLineNumber];
    }

    /**
     * The offset of the end of the given line. This is in code units.
     */
    private int getLineEndOffset(int lineNumber) {
        int realLineNumber = lineNumber - startingLine;
        if (realLineNumber <0) {
            return 0;
        }
        if (realLineNumber >= lineOffsets.length) {
            return content.length();
        }
        if (realLineNumber == lineOffsets.length -1) {
            return content.length() -1;
        }
        return lineOffsets[realLineNumber+1] -1;
    }

    /**
     * Given the line number and the column in code points,
     * returns the column in code units.
     */
    private int getCodeUnitColumn(int lineNumber, int codePointColumn) {
        int startPoint = getLineStartOffset(lineNumber);
        int suppCharsFound = 0;
        for (int i=1; i<codePointColumn;i++) {
            char first = content.charAt(startPoint++);
            if (Character.isHighSurrogate(first)) {
                char second = content.charAt(startPoint);
                if (Character.isLowSurrogate(second)) {
                    suppCharsFound++;
                    startPoint++;
                }
            }
        }
        return codePointColumn + suppCharsFound;
    }

    /**
     * @param line the line number
     * @param column the column in code _points_
     * @return the offset in code _units_
     */ 
    private int getOffset(int line, int column) {
        if (line==0) line = startingLine; // REVISIT? This should not be necessary!
        int columnAdjustment = (line == startingLine) ? startingColumn : 1;
        int codeUnitAdjustedColumn = getCodeUnitColumn(line, column);
        columnAdjustment += (codeUnitAdjustedColumn - column);
        return lineOffsets[line - startingLine] + column - columnAdjustment;
    }
    

    private static int[] createLineOffsetsTable(CharSequence content) {
        if (content.length() == 0) {
            return new int[0];
        }
        int lineCount = 0;
        int length = content.length();
        for (int i = 0; i < length; i++) {
            char ch = content.charAt(i);
            if (ch == '\n') {
                lineCount++;
            }
        }
        if (content.charAt(length - 1) != '\n') {
            lineCount++;
        }
        int[] lineOffsets = new int[lineCount];
        lineOffsets[0] = 0;
        int index = 1;
        for (int i = 0; i < length; i++) {
            char ch = content.charAt(i);
            if (ch == '\n') {
                if (i + 1 == length)
                    break;
                lineOffsets[index++] = i + 1;
            }
        }
        return lineOffsets;
    }


    public String getInputSource() {
        return inputSource;
    }
    
    void setInputSource(String inputSource) {
        this.inputSource = inputSource;
    }

    /**
     * @return the text between startOffset (inclusive)
     * and endOffset(exclusive)
     */
    String getText(int startOffset, int endOffset) {
        return content.subSequence(startOffset, endOffset).toString();
    }
    private BitSet tokenOffsets = new BitSet();
    private Map<Integer, Token> offsetToTokenMap = new HashMap<>();

    void cacheToken(Token tok) {
	    int offset = tok.getBeginOffset();
	    tokenOffsets.set(offset);
	    offsetToTokenMap.put(offset, tok);
    }

    void uncacheTokens(Token lastToken) {
        if (lastToken.getEndOffset() < tokenOffsets.length()) { //REVISIT
            tokenOffsets.clear(lastToken.getEndOffset(), tokenOffsets.length());
        }
        lastToken.setNextChainedToken(null); //undo special chaining as well.
    }

    Token getCachedToken(int offset) {
	     return tokenOffsets.get(offset) ? offsetToTokenMap.get(offset) : null;
    } 

    Token getPreviousCachedToken(int offset) {
        int prevOffset = tokenOffsets.previousSetBit(offset-1);
        return prevOffset == -1 ? null : offsetToTokenMap.get(prevOffset);
    }
    
    [#embed "InputUtils.java.ftl"]
}
